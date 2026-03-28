from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


MODULE_RENDER_ORDER = {
    "cloudflare-domain-baseline": 0,
    "cloudflare-website-acceleration": 1,
    "cloudflare-mail-foundation": 2,
    "cloudflare-preview-website": 3,
    "cloudflare-access-guard": 4,
    "cloudflare-redirect-domain": 5,
}


def write_scaffold_package(classification_report: dict[str, Any], output_dir: Path, repo_root: Path) -> list[Path]:
    scaffold_root = output_dir / "scaffold"
    scaffold_root.mkdir(parents=True, exist_ok=True)
    written_paths: list[Path] = []

    for zone_report in classification_report.get("zones") or []:
        zone_slug = slugify(zone_report.get("zone_name") or zone_report.get("zone_id") or "zone")
        zone_dir = scaffold_root / zone_slug
        zone_dir.mkdir(parents=True, exist_ok=True)
        main_tf = zone_dir / "main.tf"
        main_tf.write_text(render_zone_scaffold(zone_report, zone_dir, repo_root), encoding="utf-8")
        written_paths.append(main_tf)

    manifest_path = scaffold_root / "manifest.json"
    manifest_payload = {
        "zones": [
            {
                "zone_name": zone_report.get("zone_name"),
                "zone_id": zone_report.get("zone_id"),
                "scaffold_path": str((scaffold_root / slugify(zone_report.get("zone_name") or zone_report.get("zone_id") or "zone") / "main.tf").relative_to(output_dir)),
            }
            for zone_report in classification_report.get("zones") or []
        ]
    }
    manifest_path.write_text(json.dumps(manifest_payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    written_paths.append(manifest_path)
    return written_paths


def render_zone_scaffold(zone_report: dict[str, Any], zone_dir: Path, repo_root: Path) -> str:
    modules = sorted(
        zone_report.get("modules") or [],
        key=lambda item: (MODULE_RENDER_ORDER.get(item.get("module"), 99), item.get("instance_name") or ""),
    )
    source_is_portable = _is_within_repo(zone_dir, repo_root)
    blocks = []
    if not source_is_portable:
        blocks.append("# TODO: Module source paths below are absolute because the scaffold output\n# directory is outside the repository. Adjust them to relative paths for your\n# target project layout.")
    for module in modules:
        module_source = compute_module_source(zone_dir, repo_root, module.get("module") or "")
        lines = [f'module "{module.get("instance_name")}" {{', f'  source = {hcl_value(module_source, 2)}']
        for key, value in module.get("inputs", {}).items():
            lines.append(f"  {key} = {hcl_value(value, 2)}")
        lines.append("}")
        blocks.append("\n".join(lines))
    return "\n\n".join(blocks) + ("\n" if blocks else "")


def _is_within_repo(zone_dir: Path, repo_root: Path) -> bool:
    resolved_zone_dir = zone_dir.resolve()
    resolved_repo_root = repo_root.resolve()
    return resolved_repo_root in resolved_zone_dir.parents or resolved_zone_dir == resolved_repo_root


def compute_module_source(zone_dir: Path, repo_root: Path, module_name: str) -> str:
    module_dir = repo_root / "terraform" / "modules" / module_name
    resolved_zone_dir = zone_dir.resolve()
    resolved_repo_root = repo_root.resolve()
    if resolved_repo_root in resolved_zone_dir.parents or resolved_zone_dir == resolved_repo_root:
        try:
            return os.path.relpath(module_dir, zone_dir)
        except ValueError:
            return str(module_dir)
    return str(module_dir)


def hcl_value(value: Any, indent_level: int) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        if not value:
            return "[]"
        inner_indent = " " * (indent_level + 2)
        closing_indent = " " * indent_level
        rendered_items = [f"{inner_indent}{hcl_value(item, indent_level + 2)}," for item in value]
        return "[\n" + "\n".join(rendered_items) + f"\n{closing_indent}]"
    if isinstance(value, dict):
        if not value:
            return "{}"
        inner_indent = " " * (indent_level + 2)
        closing_indent = " " * indent_level
        rendered_items = [f"{inner_indent}{key} = {hcl_value(item, indent_level + 2)}" for key, item in value.items()]
        return "{\n" + "\n".join(rendered_items) + f"\n{closing_indent}}}"
    return json.dumps(str(value))


def slugify(value: str) -> str:
    result = []
    previous_dash = False
    for character in value.lower():
        if character.isalnum():
            result.append(character)
            previous_dash = False
        elif not previous_dash:
            result.append("-")
            previous_dash = True
    return "".join(result).strip("-") or "zone"
