from __future__ import annotations

from typing import Any


def normalize_inventory(raw_inventory: dict[str, Any]) -> dict[str, Any]:
    account = raw_inventory.get("account") or {}
    normalized_zones = [normalize_zone(bundle) for bundle in raw_inventory.get("zones") or []]
    normalized_tunnels = [normalize_tunnel(item, account.get("tunnel_configurations") or {}) for item in account.get("tunnels") or []]
    return {
        "metadata": raw_inventory.get("metadata") or {},
        "warnings": raw_inventory.get("warnings") or [],
        "account": {
            "account_id": account.get("account_id"),
            "tunnels": sorted(normalized_tunnels, key=lambda item: item.get("name") or item.get("id") or ""),
        },
        "zones": sorted(normalized_zones, key=lambda item: item.get("zone_name") or ""),
    }


def normalize_zone(zone_bundle: dict[str, Any]) -> dict[str, Any]:
    zone = zone_bundle.get("zone") or {}
    zone_name = zone.get("name")
    return {
        "zone_id": zone.get("id"),
        "zone_name": zone_name,
        "zone_status": zone.get("status"),
        "account_id": (zone.get("account") or {}).get("id"),
        "settings": {key: normalize_setting(value) for key, value in (zone_bundle.get("settings") or {}).items()},
        "dns_records": sorted(
            [normalize_dns_record(record, zone_name) for record in zone_bundle.get("dns_records") or []],
            key=lambda item: (item.get("name") or "", item.get("type") or "", item.get("content") or ""),
        ),
        "rulesets": sorted(
            [normalize_ruleset(ruleset) for ruleset in zone_bundle.get("rulesets") or []],
            key=lambda item: (item.get("phase") or "", item.get("name") or ""),
        ),
        "access_applications": sorted(
            [normalize_access_application(app) for app in zone_bundle.get("access_applications") or []],
            key=lambda item: (item.get("domain") or "", item.get("name") or ""),
        ),
    }


def normalize_setting(raw_setting: Any) -> Any:
    if isinstance(raw_setting, dict) and "value" in raw_setting:
        return raw_setting.get("value")
    return raw_setting


def normalize_dns_record(record: dict[str, Any], zone_name: str | None) -> dict[str, Any]:
    return {
        "id": record.get("id"),
        "name": record.get("name"),
        "relative_name": relative_name(record.get("name"), zone_name),
        "type": record.get("type"),
        "content": record.get("content"),
        "ttl": record.get("ttl"),
        "proxied": record.get("proxied"),
        "priority": record.get("priority"),
        "data": record.get("data"),
        "comment": record.get("comment"),
        "tags": record.get("tags") or [],
    }


def normalize_ruleset(ruleset: dict[str, Any]) -> dict[str, Any]:
    normalized_rules = []
    for rule in ruleset.get("rules") or []:
        normalized_rules.append(
            {
                "id": rule.get("id"),
                "ref": rule.get("ref"),
                "description": rule.get("description"),
                "expression": rule.get("expression"),
                "action": rule.get("action"),
                "enabled": rule.get("enabled"),
                "action_parameters": rule.get("action_parameters") or {},
            }
        )
    return {
        "id": ruleset.get("id"),
        "name": ruleset.get("name"),
        "description": ruleset.get("description"),
        "kind": ruleset.get("kind"),
        "phase": ruleset.get("phase"),
        "rules": normalized_rules,
    }


def normalize_tunnel(tunnel: dict[str, Any], tunnel_configurations: dict[str, Any]) -> dict[str, Any]:
    tunnel_id = tunnel.get("id")
    configuration = tunnel_configurations.get(tunnel_id) or {}
    ingress = extract_tunnel_ingress(configuration)
    return {
        "id": tunnel_id,
        "name": tunnel.get("name"),
        "status": tunnel.get("status"),
        "deleted_at": tunnel.get("deleted_at"),
        "config_src": tunnel.get("config_src"),
        "tunnel_cname": f"{tunnel_id}.cfargotunnel.com" if tunnel_id else None,
        "ingress": ingress,
    }


def extract_tunnel_ingress(configuration: Any) -> list[dict[str, Any]]:
    if not configuration:
        return []

    if isinstance(configuration, dict):
        if isinstance(configuration.get("config"), dict):
            config = configuration.get("config") or {}
        elif isinstance(configuration.get("result"), dict):
            return extract_tunnel_ingress(configuration.get("result"))
        else:
            config = configuration
    else:
        return []

    ingress = config.get("ingress") or config.get("ingress_rules") or []
    normalized = []
    for item in ingress:
        if not isinstance(item, dict):
            continue
        normalized.append(
            {
                "hostname": item.get("hostname"),
                "service": item.get("service"),
            }
        )
    return normalized


def normalize_access_application(app: dict[str, Any]) -> dict[str, Any]:
    domain = app.get("domain") or next(iter(app.get("self_hosted_domains") or []), None)
    policies = []
    for policy in app.get("policies") or []:
        if not isinstance(policy, dict):
            continue
        policies.append(
            {
                "id": policy.get("id"),
                "name": policy.get("name"),
                "decision": policy.get("decision"),
                "include": policy.get("include") or [],
            }
        )
    discovery = normalize_access_application_discovery(app.get("discovery"))
    return {
        "id": app.get("id"),
        "name": app.get("name"),
        "domain": domain,
        "type": app.get("type"),
        "session_duration": app.get("session_duration"),
        "policies": policies,
        "discovery": discovery,
        "scope": infer_access_application_scope(discovery),
    }


def normalize_access_application_discovery(raw_discovery: Any) -> dict[str, Any]:
    discovery = raw_discovery if isinstance(raw_discovery, dict) else {}
    scope_hints = sorted({item for item in discovery.get("scope_hints") or [] if isinstance(item, str)})
    sources = []
    for source in discovery.get("sources") or []:
        if not isinstance(source, dict):
            continue
        sources.append(
            {
                "endpoint": source.get("endpoint"),
                "path": source.get("path"),
                "query": source.get("query") if isinstance(source.get("query"), dict) else {},
                "scope_hint": source.get("scope_hint"),
            }
        )
    sources.sort(key=lambda item: (item.get("endpoint") or "", item.get("path") or ""))
    return {
        "scope_hints": scope_hints,
        "sources": sources,
    }


def infer_access_application_scope(discovery: dict[str, Any]) -> str | None:
    scope_hints = {item for item in discovery.get("scope_hints") or [] if isinstance(item, str)}
    if scope_hints == {"zone"}:
        return "zone"
    if scope_hints == {"zone", "account"}:
        return "zone"
    if scope_hints == {"account"}:
        return "account"
    return None


def relative_name(name: str | None, zone_name: str | None) -> str | None:
    if not name or not zone_name:
        return name
    normalized_name = name.rstrip(".")
    normalized_zone_name = zone_name.rstrip(".")
    if normalized_name == normalized_zone_name:
        return "@"
    suffix = f".{normalized_zone_name}"
    if normalized_name.endswith(suffix):
        return normalized_name[: -len(suffix)]
    return normalized_name
