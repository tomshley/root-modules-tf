from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
from typing import Any

from classification import classify_inventory
from cloudflare_client import CloudflareApiError, CloudflareClient
from inventory import collect_inventory
from normalization import normalize_inventory
from review import build_import_hints, build_review_summary
from scaffolding import write_scaffold_package


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    if args.command == "inventory":
        raw_inventory = run_inventory(args)
        write_raw_inventory(raw_inventory, Path(args.output_dir))
        return 0
    if args.command == "replay":
        with open(args.input, "r", encoding="utf-8") as handle:
            raw_inventory = json.load(handle)
        run_pipeline(raw_inventory, Path(args.output_dir))
        return 0
    if args.command == "run":
        raw_inventory = run_inventory(args)
        run_pipeline(raw_inventory, Path(args.output_dir))
        return 0
    parser.print_help()
    return 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="cloudflare-import", description="Read-only Cloudflare inventory, classification, and scaffold utility.")
    subparsers = parser.add_subparsers(dest="command")

    inventory_parser = subparsers.add_parser("inventory", help="Fetch raw read-only Cloudflare inventory and write inventory files.")
    add_live_arguments(inventory_parser)
    inventory_parser.add_argument("--output-dir", required=True)

    run_parser = subparsers.add_parser("run", help="Fetch Cloudflare inventory and emit normalized, classified, scaffolded review outputs.")
    add_live_arguments(run_parser)
    run_parser.add_argument("--output-dir", required=True)

    replay_parser = subparsers.add_parser("replay", help="Replay the normalize/classify/scaffold pipeline from a saved inventory JSON file.")
    replay_parser.add_argument("--input", required=True)
    replay_parser.add_argument("--output-dir", required=True)

    return parser


def add_live_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--account-id")
    parser.add_argument("--zone-id", action="append", dest="zone_ids", default=[])
    parser.add_argument("--api-token-env", default="CLOUDFLARE_API_TOKEN", help="Environment variable name holding the Cloudflare API token.")
    parser.add_argument("--base-url", default="https://api.cloudflare.com/client/v4")
    parser.add_argument("--per-page", type=int, default=100)


def run_inventory(args: argparse.Namespace) -> dict[str, Any]:
    if not args.account_id and not args.zone_ids:
        raise SystemExit("Either --account-id or at least one --zone-id is required.")
    api_token = resolve_api_token(args.api_token_env)
    client = CloudflareClient(api_token=api_token, base_url=args.base_url, per_page=args.per_page)
    try:
        return collect_inventory(client, args.account_id, args.zone_ids)
    except CloudflareApiError as exc:
        raise SystemExit(str(exc)) from exc


def resolve_api_token(api_token_env: str) -> str:
    env_value = os.getenv(api_token_env)
    if env_value:
        return env_value
    raise SystemExit(f"Cloudflare API token was not provided. Export {api_token_env} or use --api-token-env to specify a different variable.")


def run_pipeline(raw_inventory: dict[str, Any], output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    repo_root = Path(__file__).resolve().parents[2]

    raw_path = write_raw_inventory(raw_inventory, output_dir)
    normalized_inventory = normalize_inventory(raw_inventory)
    normalized_path = write_json(output_dir / "inventory" / "normalized_inventory.json", normalized_inventory)
    classification_report = classify_inventory(normalized_inventory)
    classification_path = write_json(output_dir / "classification" / "classifications.json", classification_report)
    scaffold_paths = write_scaffold_package(classification_report, output_dir, repo_root)
    review_path = write_text(output_dir / "review" / "review_summary.md", build_review_summary(classification_report))
    import_hints_path = write_text(output_dir / "review" / "import_hints.md", build_import_hints(classification_report))

    print(f"Wrote raw inventory: {raw_path}")
    print(f"Wrote normalized inventory: {normalized_path}")
    print(f"Wrote classifications: {classification_path}")
    print(f"Wrote review summary: {review_path}")
    print(f"Wrote import hints: {import_hints_path}")
    for scaffold_path in scaffold_paths:
        print(f"Wrote scaffold artifact: {scaffold_path}")


def write_raw_inventory(raw_inventory: dict[str, Any], output_dir: Path) -> Path:
    return write_json(output_dir / "inventory" / "raw_inventory.json", raw_inventory)


def write_json(path: Path, payload: dict[str, Any]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return path


def write_text(path: Path, contents: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")
    return path


if __name__ == "__main__":
    raise SystemExit(main())
