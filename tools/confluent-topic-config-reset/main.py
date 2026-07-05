from __future__ import annotations

import argparse
import os
import sys

try:
    from confluent_kafka.admin import (
        AdminClient,
        AlterConfigOpType,
        ConfigEntry,
        ConfigResource,
        ConfigSource,
    )
except ImportError as exc:  # pragma: no cover - import guard
    raise SystemExit(
        "confluent-kafka >= 2.2.0 is required (incremental_alter_configs). "
        "Install with: python3 -m pip install -r tools/confluent-topic-config-reset/requirements.txt"
    ) from exc


def source_name(entry: ConfigEntry) -> str:
    try:
        return ConfigSource(entry.source).name
    except ValueError:
        return f"UNKNOWN({entry.source})"


def is_topic_override(entry: ConfigEntry) -> bool:
    return entry.source == ConfigSource.DYNAMIC_TOPIC_CONFIG.value


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="confluent-topic-config-reset",
        description=(
            "List and reset per-topic Kafka config overrides via the native "
            "AdminClient protocol (incrementalAlterConfigs DELETE). Exists "
            "because the Terraform confluent provider plans undeclared-but-set "
            "topic configs as removals it cannot execute: the Confluent REST "
            "configs:alter DELETE path rejects typed configs with "
            "\"value 'null' is not a valid INT\" (e.g. max.message.bytes), "
            "wedging plan/apply for modules like confluent-streaming-topics. "
            "The AdminClient protocol reset succeeds and returns the config "
            "to its cluster default."
        ),
    )
    parser.add_argument(
        "--bootstrap-servers",
        default=os.environ.get("CONFLUENT_BOOTSTRAP_SERVERS", ""),
        help="Kafka bootstrap servers host:port (env: CONFLUENT_BOOTSTRAP_SERVERS).",
    )
    parser.add_argument(
        "--api-key",
        default=os.environ.get("CONFLUENT_API_KEY", ""),
        help="SASL/PLAIN username, e.g. a Confluent Cloud cluster API key (env: CONFLUENT_API_KEY).",
    )
    parser.add_argument(
        "--api-secret",
        default=os.environ.get("CONFLUENT_API_SECRET", ""),
        help="SASL/PLAIN password, e.g. a Confluent Cloud cluster API secret (env: CONFLUENT_API_SECRET).",
    )
    parser.add_argument(
        "--security-protocol",
        default="SASL_SSL",
        choices=["SASL_SSL", "PLAINTEXT"],
        help="PLAINTEXT skips auth for local brokers; SASL_SSL (default) is the Confluent Cloud posture.",
    )
    parser.add_argument("--topic", required=True, help="Topic whose config overrides are inspected/reset.")

    subcommands = parser.add_subparsers(dest="command", required=True)

    subcommands.add_parser(
        "list",
        help="Show every topic config with its source; overrides (DYNAMIC_TOPIC_CONFIG) are the reset candidates.",
    )

    reset = subcommands.add_parser(
        "reset",
        help="Reset named config overrides to the cluster default (dry-run unless --execute).",
    )
    reset.add_argument(
        "--config",
        action="append",
        required=True,
        metavar="NAME",
        help="Config name to reset, e.g. max.message.bytes. Repeatable.",
    )
    reset.add_argument(
        "--execute",
        action="store_true",
        help="Perform the reset. Without this flag the command only prints what it would do.",
    )
    return parser


def admin_client(args: argparse.Namespace) -> AdminClient:
    if not args.bootstrap_servers:
        raise SystemExit("ERROR: --bootstrap-servers (or CONFLUENT_BOOTSTRAP_SERVERS) is required")
    conf: dict[str, str] = {"bootstrap.servers": args.bootstrap_servers}
    if args.security_protocol == "SASL_SSL":
        if not args.api_key or not args.api_secret:
            raise SystemExit(
                "ERROR: --api-key/--api-secret (or CONFLUENT_API_KEY/CONFLUENT_API_SECRET) "
                "are required with SASL_SSL"
            )
        conf.update(
            {
                "security.protocol": "SASL_SSL",
                "sasl.mechanism": "PLAIN",
                "sasl.username": args.api_key,
                "sasl.password": args.api_secret,
            }
        )
    return AdminClient(conf)


def describe_topic_configs(admin: AdminClient, topic: str) -> dict[str, ConfigEntry]:
    resource = ConfigResource(ConfigResource.Type.TOPIC, topic)
    futures = admin.describe_configs([resource], request_timeout=30)
    return futures[resource].result()


def run_list(admin: AdminClient, topic: str) -> int:
    entries = describe_topic_configs(admin, topic)
    non_default = {name: e for name, e in entries.items() if not e.is_default}
    overrides = {name: e for name, e in non_default.items() if is_topic_override(e)}
    print(f"topic: {topic}")
    print(
        f"configs: {len(entries)} total, {len(non_default)} non-default, "
        f"{len(overrides)} topic-level overrides (reset candidates)"
    )
    for name in sorted(non_default):
        entry = non_default[name]
        marker = "*" if is_topic_override(entry) else " "
        print(f" {marker} {name} = {entry.value}  [{source_name(entry)}]")
    if overrides:
        print("(* = reset candidate: set at the topic level via DYNAMIC_TOPIC_CONFIG)")
    return 0


def run_reset(admin: AdminClient, topic: str, names: list[str], execute: bool) -> int:
    entries = describe_topic_configs(admin, topic)
    missing = [n for n in names if n not in entries]
    if missing:
        raise SystemExit(f"ERROR: unknown config name(s) for topic {topic}: {', '.join(missing)}")

    not_topic_level = [n for n in names if not is_topic_override(entries[n])]
    to_reset = [n for n in names if is_topic_override(entries[n])]
    for name in not_topic_level:
        print(
            f"SKIP {name}: not a topic-level override "
            f"(value {entries[name].value}, source {source_name(entries[name])})"
        )
    for name in to_reset:
        print(f"{'RESET' if execute else 'WOULD RESET'} {name}: {entries[name].value} -> cluster default")

    if not to_reset:
        print("Nothing to do.")
        return 0
    if not execute:
        print("Dry run only. Re-run with --execute to apply.")
        return 0

    resource = ConfigResource(
        ConfigResource.Type.TOPIC,
        topic,
        incremental_configs=[
            ConfigEntry(name, None, incremental_operation=AlterConfigOpType.DELETE) for name in to_reset
        ],
    )
    futures = admin.incremental_alter_configs([resource], request_timeout=30)
    futures[resource].result()

    refreshed = describe_topic_configs(admin, topic)
    for name in to_reset:
        entry = refreshed[name]
        state = f"STILL SET [{source_name(entry)}]" if is_topic_override(entry) else "no longer topic-level"
        print(f"AFTER {name} = {entry.value}  [{state}]")
    if any(is_topic_override(refreshed[name]) for name in to_reset):
        print("ERROR: some configs remain set at the topic level after reset", file=sys.stderr)
        return 1
    return 0


def main() -> int:
    args = build_parser().parse_args()
    admin = admin_client(args)
    if args.command == "list":
        return run_list(admin, args.topic)
    return run_reset(admin, args.topic, args.config, args.execute)


if __name__ == "__main__":
    raise SystemExit(main())
