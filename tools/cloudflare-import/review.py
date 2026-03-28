from __future__ import annotations

from typing import Any


def build_review_summary(classification_report: dict[str, Any]) -> str:
    zones = classification_report.get("zones") or []
    module_count = sum(len(zone.get("modules") or []) for zone in zones)
    uncertain_count = sum(1 for zone in zones for module in zone.get("modules") or [] if module.get("status") != "confident")
    lines = [
        "# Cloudflare Import Review Summary",
        "",
        f"- Zones analyzed: {len(zones)}",
        f"- Module classifications emitted: {module_count}",
        f"- Review-required classifications: {uncertain_count}",
        "",
    ]

    for zone in zones:
        lines.append(f"## {zone.get('zone_name')}")
        lines.append("")
        lines.append(f"- Zone ID: {zone.get('zone_id')}")
        lines.append(f"- Classified modules: {len(zone.get('modules') or [])}")
        if zone.get("findings"):
            for finding in zone.get("findings") or []:
                lines.append(f"- Finding: {finding}")
        for module in zone.get("modules") or []:
            lines.append(f"- {module.get('module')} ({module.get('instance_name')}): {module.get('status')} / {module.get('confidence')}")
            for finding in module.get("findings") or []:
                lines.append(f"  - Review: {finding}")
        for item in zone.get("unclassified") or []:
            lines.append(f"- Unclassified: {item}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def build_import_hints(classification_report: dict[str, Any]) -> str:
    lines = ["# Cloudflare Import Hints", ""]
    for zone in classification_report.get("zones") or []:
        lines.append(f"## {zone.get('zone_name')}")
        lines.append("")
        for module in zone.get("modules") or []:
            lines.append(f"### {module.get('instance_name')} -> {module.get('module')}")
            lines.append("")
            for hint in module.get("import_hints") or []:
                lines.append(f"- {hint}")
            if not (module.get("import_hints") or []):
                lines.append("- No import hints generated.")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"
