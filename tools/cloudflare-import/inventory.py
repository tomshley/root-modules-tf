from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from cloudflare_client import CloudflareApiError, CloudflareClient


SETTING_IDS = [
    "ssl",
    "min_tls_version",
    "always_use_https",
    "security_header",
    "brotli",
    "polish",
    "mirage",
    "early_hints",
    "bot_fight_mode",
]


def collect_inventory(client: CloudflareClient, account_id: str | None, zone_ids: list[str] | None = None) -> dict[str, Any]:
    warnings: list[str] = []
    zones = _fetch_zones(client, account_id, zone_ids or [], warnings)
    tunnels = _fetch_tunnels(client, account_id, warnings) if account_id else []
    tunnel_configurations = _fetch_tunnel_configurations(client, account_id, tunnels, warnings) if account_id else {}

    zone_bundles = []
    for zone in zones:
        zone_bundles.append(
            {
                "zone": zone,
                "settings": _fetch_zone_settings(client, zone["id"], warnings),
                "dns_records": _fetch_optional_paginated(
                    client,
                    f"/zones/{zone['id']}/dns_records",
                    warnings,
                    f"dns records for zone {zone['id']}",
                ),
                "rulesets": _fetch_optional_paginated(
                    client,
                    f"/zones/{zone['id']}/rulesets",
                    warnings,
                    f"rulesets for zone {zone['id']}",
                ),
                "access_applications": _fetch_access_applications(client, account_id, zone["id"], zone.get("name"), warnings),
            }
        )

    return {
        "metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "account_id": account_id,
            "requested_zone_ids": zone_ids or [],
            "api_base_url": client.base_url,
        },
        "warnings": warnings,
        "account": {
            "account_id": account_id,
            "tunnels": tunnels,
            "tunnel_configurations": tunnel_configurations,
        },
        "zones": zone_bundles,
    }


def _fetch_zones(client: CloudflareClient, account_id: str | None, zone_ids: list[str], warnings: list[str]) -> list[dict[str, Any]]:
    zones: list[dict[str, Any]] = []
    if zone_ids:
        for zone_id in zone_ids:
            try:
                result = client.get_result(f"/zones/{zone_id}")
            except CloudflareApiError as exc:
                warnings.append(f"Failed to fetch zone {zone_id}: {exc}")
                continue
            if isinstance(result, dict):
                zones.append(result)
    else:
        query = {"account.id": account_id} if account_id else None
        try:
            discovered = client.get_paginated("/zones", query)
        except CloudflareApiError as exc:
            raise CloudflareApiError(f"Failed to enumerate zones: {exc}") from exc
        zones = discovered

    return sorted(zones, key=lambda item: item.get("name", ""))


def _fetch_tunnels(client: CloudflareClient, account_id: str, warnings: list[str]) -> list[dict[str, Any]]:
    attempts = [
        (f"/accounts/{account_id}/cfd_tunnel", {"is_deleted": "false"}),
        (f"/accounts/{account_id}/cfd_tunnel", None),
        (f"/accounts/{account_id}/tunnels", None),
    ]
    for path, query in attempts:
        try:
            return client.get_paginated(path, query)
        except CloudflareApiError as exc:
            warnings.append(f"Failed tunnel inventory via {path}: {exc}")
    return []


def _fetch_tunnel_configurations(
    client: CloudflareClient,
    account_id: str,
    tunnels: list[dict[str, Any]],
    warnings: list[str],
) -> dict[str, Any]:
    configurations: dict[str, Any] = {}
    for tunnel in tunnels:
        tunnel_id = tunnel.get("id")
        if not tunnel_id:
            continue
        attempts = [
            f"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/configurations",
            f"/accounts/{account_id}/cfd_tunnel/{tunnel_id}/config",
        ]
        for path in attempts:
            try:
                configurations[tunnel_id] = client.get_result(path)
                break
            except CloudflareApiError as exc:
                warnings.append(f"Failed tunnel configuration inventory via {path}: {exc}")
    return configurations


def _fetch_zone_settings(client: CloudflareClient, zone_id: str, warnings: list[str]) -> dict[str, Any]:
    settings: dict[str, Any] = {}
    for setting_id in SETTING_IDS:
        try:
            settings[setting_id] = client.get_result(f"/zones/{zone_id}/settings/{setting_id}")
        except CloudflareApiError as exc:
            warnings.append(f"Failed zone setting inventory for {zone_id}/{setting_id}: {exc}")
    return settings


def _fetch_access_applications(
    client: CloudflareClient,
    account_id: str | None,
    zone_id: str,
    zone_name: str | None,
    warnings: list[str],
) -> list[dict[str, Any]]:
    attempts: list[tuple[str, dict[str, Any] | None, str]] = [(f"/zones/{zone_id}/access/apps", None, "zone")]
    if account_id:
        attempts.extend(
            [
                (f"/accounts/{account_id}/access/apps", {"zone_id": zone_id}, "account"),
                (f"/accounts/{account_id}/access/apps", None, "account"),
            ]
        )

    merged_apps: dict[str, dict[str, Any]] = {}
    for path, query, discovery_endpoint in attempts:
        try:
            apps = client.get_paginated(path, query)
        except CloudflareApiError as exc:
            warnings.append(f"Failed access application inventory via {path}: {exc}")
            continue
        for app in _filter_access_apps_by_zone(apps, zone_name):
            merge_key = _access_application_merge_key(app, discovery_endpoint)
            merged_apps[merge_key] = _merge_access_application(
                merged_apps.get(merge_key),
                app,
                path,
                query,
                discovery_endpoint,
            )

    return sorted(
        merged_apps.values(),
        key=lambda item: (item.get("domain") or "", item.get("name") or "", item.get("id") or ""),
    )


def _access_application_merge_key(app: dict[str, Any], discovery_endpoint: str) -> str:
    if app.get("id"):
        return f"id:{app['id']}"
    return ":".join(
        [
            discovery_endpoint,
            app.get("domain") or "",
            app.get("name") or "",
            ",".join(sorted(app.get("self_hosted_domains") or [])),
        ]
    )


def _merge_access_application(
    existing: dict[str, Any] | None,
    candidate: dict[str, Any],
    path: str,
    query: dict[str, Any] | None,
    discovery_endpoint: str,
) -> dict[str, Any]:
    source_entry = {
        "endpoint": discovery_endpoint,
        "path": path,
        "query": dict(query or {}),
        "scope_hint": discovery_endpoint,
    }
    if not existing:
        merged = dict(candidate)
        merged["discovery"] = {
            "scope_hints": [discovery_endpoint],
            "sources": [source_entry],
        }
        return merged

    merged = dict(existing)
    for key, value in candidate.items():
        if key == "discovery":
            continue
        if key == "self_hosted_domains":
            existing_domains = [item for item in merged.get(key) or [] if isinstance(item, str)]
            candidate_domains = [item for item in value or [] if isinstance(item, str)] if isinstance(value, list) else []
            merged[key] = sorted(set(existing_domains + candidate_domains))
            continue
        if key == "policies":
            existing_policies = merged.get(key) or []
            candidate_policies = value if isinstance(value, list) else []
            if len(candidate_policies) > len(existing_policies):
                merged[key] = candidate_policies
            continue
        if merged.get(key) in (None, "", []):
            merged[key] = value

    discovery = dict(merged.get("discovery") or {})
    scope_hints = [item for item in discovery.get("scope_hints") or [] if isinstance(item, str)]
    if discovery_endpoint not in scope_hints:
        scope_hints.append(discovery_endpoint)
    discovery["scope_hints"] = sorted(scope_hints)

    sources = [item for item in discovery.get("sources") or [] if isinstance(item, dict)]
    if not any(
        item.get("endpoint") == source_entry["endpoint"]
        and item.get("path") == source_entry["path"]
        and item.get("query") == source_entry["query"]
        for item in sources
    ):
        sources.append(source_entry)
    discovery["sources"] = sources
    merged["discovery"] = discovery
    return merged


def _filter_access_apps_by_zone(apps: list[dict[str, Any]], zone_name: str | None) -> list[dict[str, Any]]:
    if not zone_name:
        return apps
    normalized_zone = zone_name.rstrip(".")
    filtered = []
    for app in apps:
        domains = [app.get("domain")] if app.get("domain") else []
        domains.extend(app.get("self_hosted_domains") or [])
        domain_values = [value.rstrip(".") for value in domains if value]
        if any(value == normalized_zone or value.endswith(f".{normalized_zone}") for value in domain_values):
            filtered.append(app)
    return filtered


def _fetch_optional_paginated(
    client: CloudflareClient,
    path: str,
    warnings: list[str],
    label: str,
    query: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    try:
        return client.get_paginated(path, query)
    except CloudflareApiError as exc:
        warnings.append(f"Failed to fetch {label}: {exc}")
        return []
