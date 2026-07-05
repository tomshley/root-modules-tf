# confluent-topic-config-reset

`tools/confluent-topic-config-reset/` resets per-topic Kafka config overrides to their cluster defaults using the native Kafka AdminClient protocol (`incrementalAlterConfigs` with a `DELETE` op).

## Why this exists

The `confluent-streaming-topics` module (and any Terraform-managed topic) can drift when a topic config is set out-of-band — by a UI edit, a CLI touch, or topic creation with explicit values. The Terraform `confluent` provider then plans the undeclared config as a removal:

```text
~ config = {
    - "max.message.bytes" = "2097164" -> null
  }
```

and the apply fails, because the provider drives the Confluent REST `configs:alter` path, which rejects the delete for typed configs:

```text
Error: 400 Bad Request: Config property 'max.message.bytes' with value 'null' is not a valid INT.
```

The same reset succeeds over the native AdminClient protocol — the broker interprets the incremental `DELETE` as "return to default", the same operation `kafka-configs.sh --alter --delete-config` performs. This tool is that one operation, with a review-first workflow.

It never sets values, never touches partitions or cleanup policies, and never deletes topics: the only mutation it can perform is "remove a topic-level override so the cluster default applies again". Reset a config only when the default is what you want — check the current value with `list` first.

## Usage

Dependencies (any Python >= 3.9):

```bash
python3 -m pip install -r tools/confluent-topic-config-reset/requirements.txt
```

Credentials via environment (cluster API key with topic-config authority):

```bash
export CONFLUENT_BOOTSTRAP_SERVERS="pkc-xxxxx.us-east-1.aws.confluent.cloud:9092"
export CONFLUENT_API_KEY="..."
export CONFLUENT_API_SECRET="..."
```

Inspect which configs are set at the topic level (the reset candidates):

```bash
python3 tools/confluent-topic-config-reset/main.py --topic my-topic list
```

Dry-run a reset (default — prints what would change, mutates nothing):

```bash
python3 tools/confluent-topic-config-reset/main.py --topic my-topic \
  reset --config max.message.bytes --config delete.retention.ms
```

Execute it:

```bash
python3 tools/confluent-topic-config-reset/main.py --topic my-topic \
  reset --config max.message.bytes --config delete.retention.ms --execute
```

The command re-describes the topic afterwards and fails non-zero if any requested config is still set at the topic level.

Local brokers without auth are supported with `--security-protocol PLAINTEXT`.

## Typical Terraform recovery flow

1. `terraform plan` shows `-"some.config" = "..." -> null` on a managed topic and apply 400s.
2. `list` the topic here; confirm the override's value (usually it already equals the cluster default).
3. `reset --config some.config --execute`.
4. Re-run `terraform plan` — the topic diff is gone.
