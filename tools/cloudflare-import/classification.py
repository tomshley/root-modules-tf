from __future__ import annotations

import re
from typing import Any


STANDARD_PROFILE = {
    "edge_ttl_static": 14400,
    "browser_ttl_static": 3600,
    "edge_ttl_immutable": 2592000,
    "browser_ttl_immutable": 604800,
    "enable_brotli": True,
    "enable_polish": "off",
    "enable_mirage": False,
    "enable_early_hints": False,
}

AGGRESSIVE_PROFILE = {
    "edge_ttl_static": 2592000,
    "browser_ttl_static": 604800,
    "edge_ttl_immutable": 31536000,
    "browser_ttl_immutable": 31536000,
    "enable_brotli": True,
    "enable_polish": "lossless",
    "enable_mirage": True,
    "enable_early_hints": True,
}

TUNNEL_TARGET_RE = re.compile(r"^(?P<tunnel_id>[a-zA-Z0-9-]+)\.cfargotunnel\.com\.?$")


def classify_inventory(normalized_inventory: dict[str, Any]) -> dict[str, Any]:
    """Classify a **normalized** inventory into module assignments.

    The inventory must have been processed by ``normalize_inventory`` first.
    Passing raw API output will produce incorrect classifications because
    settings would still be wrapped in ``{"id": ..., "value": ...}`` objects.
    """
    for zone in normalized_inventory.get("zones") or []:
        for _key, setting in (zone.get("settings") or {}).items():
            if isinstance(setting, dict) and "id" in setting and "value" in setting:
                raise ValueError(
                    "classify_inventory received raw (un-normalized) inventory. "
                    "Pass the output of normalize_inventory instead."
                )
    tunnels = normalized_inventory.get("account", {}).get("tunnels") or []
    tunnels_by_id = {tunnel.get("id"): tunnel for tunnel in tunnels if tunnel.get("id")}
    zone_reports = [classify_zone(zone, tunnels_by_id) for zone in normalized_inventory.get("zones") or []]
    return {
        "metadata": normalized_inventory.get("metadata") or {},
        "warnings": normalized_inventory.get("warnings") or [],
        "zones": zone_reports,
    }


def classify_zone(zone: dict[str, Any], tunnels_by_id: dict[str, dict[str, Any]]) -> dict[str, Any]:
    modules: list[dict[str, Any]] = []
    findings: list[str] = []
    redirect_zone = classify_redirect_domain(zone)
    if redirect_zone:
        modules.append(redirect_zone)
        findings.append("Detected redirect-only zone pattern.")
    else:
        baseline_module = classify_domain_baseline(zone)
        modules.append(baseline_module)
        website_module = classify_website_acceleration(zone)
        if website_module:
            modules.append(website_module)
            canonical = (website_module.get("inputs") or {}).get("canonical_redirect")
            if canonical and canonical != "none":
                baseline_records = (baseline_module.get("inputs") or {}).get("dns_records") or []
                has_www_cname = any(
                    r.get("type") == "CNAME" and (r.get("name") or "").lower().startswith("www")
                    for r in baseline_records
                )
                if has_www_cname:
                    baseline_module.setdefault("findings", []).append(
                        f"A www CNAME record is managed by domain-baseline while website-acceleration uses canonical_redirect={canonical}. "
                        "The www CNAME may be redundant and could cause split-ownership; review whether it should be removed from dns_records."
                    )

    mail_module = classify_mail_foundation(zone)
    if mail_module:
        modules.append(mail_module)

    modules.extend(classify_preview_websites(zone, tunnels_by_id))
    modules.extend(classify_access_guards(zone))

    unclassified = find_unclassified_artifacts(zone)
    return {
        "zone_id": zone.get("zone_id"),
        "zone_name": zone.get("zone_name"),
        "modules": modules,
        "findings": findings,
        "unclassified": unclassified,
    }


def classify_domain_baseline(zone: dict[str, Any]) -> dict[str, Any]:
    zone_name = zone.get("zone_name") or "zone"
    has_full_redirect_placeholder = _has_redirect_placeholder_pair(zone.get("dns_records") or [], zone_name)
    curated_records = []
    for record in zone.get("dns_records") or []:
        if is_mail_record(record):
            continue
        if is_preview_record(record):
            continue
        if has_full_redirect_placeholder and is_redirect_placeholder_record(record, zone_name):
            continue
        if record.get("type") not in {"A", "AAAA", "CNAME", "TXT", "CAA"}:
            continue
        item = {
            "name": record.get("name"),
            "type": record.get("type"),
        }
        if record.get("type") == "CAA":
            item["caa"] = {
                "flags": ((record.get("data") or {}).get("flags") if isinstance(record.get("data"), dict) else 0) or 0,
                "tag": ((record.get("data") or {}).get("tag") if isinstance(record.get("data"), dict) else "issue"),
                "value": ((record.get("data") or {}).get("value") if isinstance(record.get("data"), dict) else "REVIEW_REQUIRED_CAA_VALUE"),
            }
        else:
            item["value"] = record.get("content")
            if record.get("type") in {"A", "AAAA", "CNAME"} and record.get("proxied") is not None:
                item["proxied"] = record.get("proxied")
        if record.get("ttl") is not None:
            item["ttl"] = record.get("ttl")
        curated_records.append(item)

    settings = zone.get("settings") or {}
    return {
        "module": "cloudflare-domain-baseline",
        "instance_name": module_instance_name("cloudflare_domain_baseline", zone_name),
        "status": "confident",
        "confidence": "high",
        "inputs": {
            "zone_id": zone.get("zone_id"),
            "ssl_mode": settings.get("ssl") or "strict",
            "min_tls_version": settings.get("min_tls_version") or "1.2",
            "dns_records": curated_records,
        },
        "findings": ["Origin CA inventory is not reconstructed in this MVP."],
        "import_hints": [
            f"module.{module_instance_name('cloudflare_domain_baseline', zone_name)}.cloudflare_zone_setting.ssl <= zone {zone.get('zone_id')} setting ssl",
            f"module.{module_instance_name('cloudflare_domain_baseline', zone_name)}.cloudflare_zone_setting.min_tls_version <= zone {zone.get('zone_id')} setting min_tls_version",
        ],
    }


def classify_mail_foundation(zone: dict[str, Any]) -> dict[str, Any] | None:
    zone_name = zone.get("zone_name") or "zone"
    mx_records = []
    spf_value = None
    dmarc_value = None
    dkim_records = []
    findings: list[str] = []

    for record in zone.get("dns_records") or []:
        record_type = record.get("type")
        relative_name = record.get("relative_name")
        content = record.get("content")
        if record_type == "MX":
            mx_records.append({"priority": record.get("priority") or 0, "value": content})
        elif record_type == "TXT" and relative_name == "@" and isinstance(content, str) and content.startswith("v=spf1") and spf_value is None:
            spf_value = content
        elif record_type == "TXT" and relative_name == "_dmarc" and isinstance(content, str) and content.startswith("v=DMARC1") and dmarc_value is None:
            dmarc_value = content
        elif record_type in {"CNAME", "TXT"} and isinstance(relative_name, str) and "_domainkey" in relative_name:
            dkim_records.append({"name": relative_name, "type": record_type, "value": content})

    if not any([mx_records, spf_value, dmarc_value, dkim_records]):
        return None

    if not spf_value:
        findings.append("SPF TXT record was not found; scaffold uses a permissive placeholder that must be reviewed.")
    if not dmarc_value:
        findings.append("DMARC TXT record was not found; scaffold uses a permissive placeholder that must be reviewed.")

    status = "confident" if spf_value and dmarc_value else "review_required"
    confidence = "high" if spf_value and dmarc_value else "medium"
    return {
        "module": "cloudflare-mail-foundation",
        "instance_name": module_instance_name("cloudflare_mail_foundation", zone_name),
        "status": status,
        "confidence": confidence,
        "inputs": {
            "zone_id": zone.get("zone_id"),
            "mx_records": sorted(mx_records, key=lambda item: (item["priority"], item["value"] or "")),
            "spf_value": spf_value or "v=spf1 ~all",
            "dkim_records": dkim_records,
            "dmarc_value": dmarc_value or "v=DMARC1; p=none",
            "verification_records": [],
        },
        "findings": findings,
        "import_hints": [
            f"module.{module_instance_name('cloudflare_mail_foundation', zone_name)}.cloudflare_dns_record.spf <= TXT SPF record in zone {zone.get('zone_id')}",
            f"module.{module_instance_name('cloudflare_mail_foundation', zone_name)}.cloudflare_dns_record.dmarc <= TXT DMARC record in zone {zone.get('zone_id')}",
        ],
    }


def classify_website_acceleration(zone: dict[str, Any]) -> dict[str, Any] | None:
    settings = zone.get("settings") or {}
    cache_ruleset = first_ruleset(zone, "http_request_cache_settings")
    dynamic_redirect_ruleset = first_ruleset(zone, "http_request_dynamic_redirect")
    website_like = any(
        [
            cache_ruleset is not None,
            dynamic_redirect_ruleset is not None,
            setting_to_bool(settings.get("always_use_https")) is True,
            settings.get("polish") not in (None, "off"),
            setting_to_bool(settings.get("mirage")) is True,
            setting_to_bool(settings.get("early_hints")) is True,
            setting_to_bool(settings.get("bot_fight_mode")) is True,
        ]
    )
    if not website_like:
        return None

    findings: list[str] = []
    extracted_cache = extract_cache_rule_inputs(cache_ruleset)
    raw_settings = {
        "enable_brotli": setting_to_bool(settings.get("brotli")),
        "enable_polish": settings.get("polish") if settings.get("polish") is not None else None,
        "enable_mirage": setting_to_bool(settings.get("mirage")),
        "enable_early_hints": setting_to_bool(settings.get("early_hints")),
    }
    extracted_settings = {key: value for key, value in raw_settings.items() if value is not None}
    missing_profile_settings = [key for key, value in raw_settings.items() if value is None]
    matched_profile = match_profile(extracted_cache | extracted_settings)
    canonical_redirect = extract_canonical_redirect(dynamic_redirect_ruleset)
    status = "confident"
    confidence = "high"
    hsts_max_age = extract_hsts_max_age(settings.get("security_header"))
    hsts_include_subdomains = extract_hsts_include_subdomains(settings.get("security_header"))
    hsts_preload = extract_hsts_preload(settings.get("security_header"))
    bot_fight_mode = setting_to_bool(settings.get("bot_fight_mode"))
    if matched_profile is None:
        matched_profile = "standard"
        status = "review_required"
        confidence = "medium"
        if missing_profile_settings:
            findings.append(
                "Website-acceleration settings were missing during inventory "
                f"({', '.join(sorted(missing_profile_settings))}); performance_profile is a review placeholder and only observed overrides were scaffolded."
            )
        else:
            findings.append("Cache/settings profile did not exactly match standard or aggressive; explicit overrides were scaffolded.")

    missing_hsts_inputs = []
    if hsts_max_age is None:
        missing_hsts_inputs.append("hsts_max_age")
    if hsts_include_subdomains is None:
        missing_hsts_inputs.append("hsts_include_subdomains")
    if hsts_preload is None:
        missing_hsts_inputs.append("hsts_preload")
    if missing_hsts_inputs:
        status = "review_required"
        confidence = "medium"
        findings.append(
            "HSTS-related settings were missing during inventory "
            f"({', '.join(missing_hsts_inputs)}); the scaffold omits authoritative HSTS overrides and requires review."
        )

    if bot_fight_mode is None:
        status = "review_required"
        confidence = "medium"
        findings.append("Bot Fight Mode setting was missing during inventory; the scaffold omits an authoritative enable_bot_fight_mode value and requires review.")

    inputs: dict[str, Any] = {
        "zone_id": zone.get("zone_id"),
        "performance_profile": matched_profile,
        "canonical_redirect": canonical_redirect or "none",
    }

    if bot_fight_mode is not None:
        inputs["enable_bot_fight_mode"] = bot_fight_mode
    if hsts_max_age is not None:
        inputs["hsts_max_age"] = hsts_max_age
    if hsts_include_subdomains is not None:
        inputs["hsts_include_subdomains"] = hsts_include_subdomains
    if hsts_preload is not None:
        inputs["hsts_preload"] = hsts_preload

    comparison_profile = STANDARD_PROFILE if matched_profile == "standard" else AGGRESSIVE_PROFILE
    extracted_overrides = {**extracted_cache, **extracted_settings}
    for key, value in extracted_overrides.items():
        if key in comparison_profile and comparison_profile[key] != value:
            inputs[key] = value

    return {
        "module": "cloudflare-website-acceleration",
        "instance_name": module_instance_name("cloudflare_website_acceleration", zone.get("zone_name") or "zone"),
        "status": status,
        "confidence": confidence,
        "inputs": inputs,
        "findings": findings,
        "import_hints": [
            f"module.{module_instance_name('cloudflare_website_acceleration', zone.get('zone_name') or 'zone')}.cloudflare_ruleset.cache <= zone {zone.get('zone_id')} cache ruleset",
            f"module.{module_instance_name('cloudflare_website_acceleration', zone.get('zone_name') or 'zone')}.cloudflare_ruleset.redirect <= zone {zone.get('zone_id')} canonical redirect ruleset when present",
        ],
    }


def classify_preview_websites(zone: dict[str, Any], tunnels_by_id: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    results = []
    for record in zone.get("dns_records") or []:
        if not is_preview_record(record):
            continue
        match = TUNNEL_TARGET_RE.match(record.get("content") or "")
        tunnel_id = match.group("tunnel_id") if match else None
        tunnel = tunnels_by_id.get(tunnel_id or "") or {}
        origin_url = lookup_tunnel_origin_url(tunnel, record.get("name"))
        findings = ["Tunnel secret cannot be recovered through the read-only API and is left as a review placeholder."]
        status = "review_required"
        confidence = "medium"
        if tunnel_id and tunnel:
            confidence = "high"
        if not origin_url:
            origin_url = "REVIEW_REQUIRED_ORIGIN_URL"
            findings.append("Tunnel ingress origin URL was not recovered and must be reviewed.")
        results.append(
            {
                "module": "cloudflare-preview-website",
                "instance_name": module_instance_name("cloudflare_preview_website", record.get("name") or zone.get("zone_name") or "zone"),
                "status": status,
                "confidence": confidence,
                "inputs": {
                    "zone_id": zone.get("zone_id"),
                    "account_id": zone.get("account_id") or "REVIEW_REQUIRED_ACCOUNT_ID",
                    "tunnel_name": tunnel.get("name") or f"review-{(tunnel_id or 'tunnel')[:12]}",
                    # tunnel_secret must be replaced with the actual tunnel secret (32 bytes, Base64-encoded)
                    "tunnel_secret": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
                    "preview_hostname": record.get("name"),
                    "origin_url": origin_url,
                },
                "findings": findings,
                "import_hints": [
                    f"module.{module_instance_name('cloudflare_preview_website', record.get('name') or zone.get('zone_name') or 'zone')}.cloudflare_zero_trust_tunnel_cloudflared.preview <= tunnel {tunnel_id or 'REVIEW_REQUIRED'}",
                    f"module.{module_instance_name('cloudflare_preview_website', record.get('name') or zone.get('zone_name') or 'zone')}.cloudflare_dns_record.preview <= DNS record {record.get('id')}",
                ],
            }
        )
    return results


def classify_access_guards(zone: dict[str, Any]) -> list[dict[str, Any]]:
    results = []
    for app in zone.get("access_applications") or []:
        if app.get("type") != "self_hosted":
            continue
        allowed_emails, allowed_domains = extract_policy_includes(app.get("policies") or [])
        findings: list[str] = []
        status = "confident"
        confidence = "high"
        scope = app.get("scope")
        inputs: dict[str, Any] = {
            "hostname": app.get("domain") or "REVIEW_REQUIRED_HOSTNAME",
            "application_name": app.get("name") or "REVIEW_REQUIRED_APPLICATION_NAME",
            "allowed_emails": allowed_emails,
            "allowed_email_domains": allowed_domains,
            "session_duration": app.get("session_duration") or "24h",
        }
        if scope == "zone":
            inputs["zone_id"] = zone.get("zone_id")
        elif scope == "account":
            inputs["account_id"] = zone.get("account_id")
        else:
            status = "review_required"
            confidence = "medium"
            findings.append(
                f"Access application scope could not be safely determined from discovery metadata: {describe_access_scope(app.get('discovery') or {})}."
            )
        if not allowed_emails and not allowed_domains:
            status = "review_required"
            confidence = "medium"
            allowed_domains = ["review-required.invalid"]
            inputs["allowed_email_domains"] = allowed_domains
            findings.append("Access policy include rules could not be reconstructed; a placeholder domain was scaffolded.")
        results.append(
            {
                "module": "cloudflare-access-guard",
                "instance_name": module_instance_name("cloudflare_access_guard", app.get("domain") or zone.get("zone_name") or "zone"),
                "status": status,
                "confidence": confidence,
                "inputs": inputs,
                "findings": findings,
                "import_hints": [
                    f"module.{module_instance_name('cloudflare_access_guard', app.get('domain') or zone.get('zone_name') or 'zone')}.cloudflare_zero_trust_access_application.guard <= access application {app.get('id')}",
                ],
            }
        )
    return results


def describe_access_scope(discovery: dict[str, Any]) -> str:
    scope_hints = sorted({item for item in discovery.get("scope_hints") or [] if isinstance(item, str)})
    if not scope_hints:
        return "no scope hints available"
    return ", ".join(scope_hints)


def classify_redirect_domain(zone: dict[str, Any]) -> dict[str, Any] | None:
    zone_name = zone.get("zone_name") or "zone"
    apex_placeholder = next((record for record in zone.get("dns_records") or [] if is_apex_name(record.get("name"), zone_name) and record.get("type") == "A" and record.get("content") == "192.0.2.1" and record.get("proxied") is True), None)
    www_placeholder = next((record for record in zone.get("dns_records") or [] if record.get("relative_name") == "www" and record.get("type") == "CNAME" and _strip_dot(record.get("content") or "") == _strip_dot(zone_name) and record.get("proxied") is True), None)
    redirect_ruleset = first_ruleset(zone, "http_request_dynamic_redirect")
    redirect_rule = None
    if redirect_ruleset:
        for rule in redirect_ruleset.get("rules") or []:
            expression = rule.get("expression") or ""
            if zone_name in expression and f"www.{zone_name}" in expression and rule.get("action") == "redirect":
                redirect_rule = rule
                break
    if not (apex_placeholder and www_placeholder and redirect_rule):
        return None

    target_expression = (((redirect_rule.get("action_parameters") or {}).get("from_value") or {}).get("target_url") or {}).get("expression") or ""
    return {
        "module": "cloudflare-redirect-domain",
        "instance_name": module_instance_name("cloudflare_redirect_domain", zone_name),
        "status": "confident",
        "confidence": "high",
        "inputs": {
            "zone_name": zone_name,
            "account_id": zone.get("account_id") or "REVIEW_REQUIRED_ACCOUNT_ID",
            "redirect_target": extract_redirect_target(target_expression) or "REVIEW_REQUIRED_REDIRECT_TARGET",
            "redirect_code": (((redirect_rule.get("action_parameters") or {}).get("from_value") or {}).get("status_code") or 301),
            "preserve_path": "http.request.uri.path" in target_expression,
            "preserve_query": bool((((redirect_rule.get("action_parameters") or {}).get("from_value") or {}).get("preserve_query_string"))),
        },
        "findings": [],
        "import_hints": [
            f"module.{module_instance_name('cloudflare_redirect_domain', zone_name)}.cloudflare_zone.redirect <= zone {zone.get('zone_id')}",
            f"module.{module_instance_name('cloudflare_redirect_domain', zone_name)}.cloudflare_ruleset.redirect <= ruleset {redirect_ruleset.get('id')}",
        ],
    }


def find_unclassified_artifacts(zone: dict[str, Any]) -> list[str]:
    notes: list[str] = []
    covered_record_types = {"A", "AAAA", "CNAME", "TXT", "CAA", "MX"}
    for record in zone.get("dns_records") or []:
        if record.get("type") not in covered_record_types:
            notes.append(f"Unhandled DNS record type {record.get('type')} at {record.get('name')}.")
    for ruleset in zone.get("rulesets") or []:
        phase = ruleset.get("phase")
        if phase not in {"http_request_cache_settings", "http_request_dynamic_redirect"}:
            notes.append(f"Unhandled ruleset phase {phase} on zone {zone.get('zone_name')}.")
    return notes


def extract_cache_rule_inputs(cache_ruleset: dict[str, Any] | None) -> dict[str, Any]:
    result: dict[str, Any] = {}
    if not cache_ruleset:
        return result
    immutable_rule = next((rule for rule in cache_ruleset.get("rules") or [] if rule.get("ref") == "cache_immutable_assets"), None)
    static_rule = next((rule for rule in cache_ruleset.get("rules") or [] if rule.get("ref") == "cache_static_assets"), None)
    if immutable_rule:
        result["edge_ttl_immutable"] = nested_get(immutable_rule, "action_parameters", "edge_ttl", "default")
        result["browser_ttl_immutable"] = nested_get(immutable_rule, "action_parameters", "browser_ttl", "default")
    if static_rule:
        result["edge_ttl_static"] = nested_get(static_rule, "action_parameters", "edge_ttl", "default")
        result["browser_ttl_static"] = nested_get(static_rule, "action_parameters", "browser_ttl", "default")
    return {key: value for key, value in result.items() if value is not None}


def match_profile(values: dict[str, Any]) -> str | None:
    standard_ok = all(key in values and values[key] == value for key, value in STANDARD_PROFILE.items())
    aggressive_ok = all(key in values and values[key] == value for key, value in AGGRESSIVE_PROFILE.items())
    if standard_ok:
        return "standard"
    if aggressive_ok:
        return "aggressive"
    return None


def extract_canonical_redirect(ruleset: dict[str, Any] | None) -> str | None:
    if not ruleset:
        return None
    for rule in ruleset.get("rules") or []:
        expression = rule.get("expression") or ""
        target_expression = nested_get(rule, "action_parameters", "from_value", "target_url", "expression") or ""
        if expression == 'http.host eq concat("www.", cf.zone.name)' and target_expression == 'concat("https://", cf.zone.name, http.request.uri.path)':
            return "www-to-apex"
        if expression == 'http.host eq cf.zone.name' and target_expression == 'concat("https://www.", cf.zone.name, http.request.uri.path)':
            return "apex-to-www"
    return None


def extract_hsts_max_age(security_header: Any) -> int | None:
    hsts = nested_get(security_header, "strict_transport_security") or {}
    max_age = hsts.get("max_age")
    if max_age is None:
        return None
    return int(max_age)


def extract_hsts_include_subdomains(security_header: Any) -> bool | None:
    hsts = nested_get(security_header, "strict_transport_security") or {}
    include_subdomains = hsts.get("include_subdomains")
    if include_subdomains is None:
        return None
    return bool(include_subdomains)


def extract_hsts_preload(security_header: Any) -> bool | None:
    hsts = nested_get(security_header, "strict_transport_security") or {}
    preload = hsts.get("preload")
    if preload is None:
        return None
    return bool(preload)


def lookup_tunnel_origin_url(tunnel: dict[str, Any], hostname: str | None) -> str | None:
    if not hostname:
        return None
    normalized_hostname = _strip_dot(hostname)
    for ingress in tunnel.get("ingress") or []:
        if _strip_dot(ingress.get("hostname") or "") == normalized_hostname:
            return ingress.get("service")
    return None


def extract_policy_includes(policies: list[dict[str, Any]]) -> tuple[list[str], list[str]]:
    emails: list[str] = []
    domains: list[str] = []
    for policy in policies:
        for include_item in policy.get("include") or []:
            if not isinstance(include_item, dict):
                continue
            if "email" in include_item:
                emails.extend(extract_string_values(include_item.get("email"), "email"))
            if "email_domain" in include_item:
                domains.extend(extract_string_values(include_item.get("email_domain"), "domain"))
    return sorted(set(filter(None, emails))), sorted(set(filter(None, domains)))


def extract_string_values(payload: Any, nested_key: str) -> list[str]:
    if isinstance(payload, str):
        return [payload]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, str)]
    if isinstance(payload, dict):
        nested = payload.get(nested_key)
        if isinstance(nested, str):
            return [nested]
        if isinstance(nested, list):
            return [item for item in nested if isinstance(item, str)]
    return []


def first_ruleset(zone: dict[str, Any], phase: str) -> dict[str, Any] | None:
    return next((ruleset for ruleset in zone.get("rulesets") or [] if ruleset.get("phase") == phase), None)


def setting_to_bool(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() == "on"
    return bool(value)


def extract_redirect_target(expression: str) -> str | None:
    concat_match = re.match(r'concat\("https://([^\"]+)",\s*http\.request\.uri\.path\)', expression)
    if concat_match:
        return concat_match.group(1)
    literal_match = re.match(r'"https://([^/"]+)/?"', expression)
    if literal_match:
        return literal_match.group(1)
    return None


def is_mail_record(record: dict[str, Any]) -> bool:
    relative_name = record.get("relative_name")
    if record.get("type") == "MX":
        return True
    if record.get("type") == "TXT" and relative_name == "@" and isinstance(record.get("content"), str) and record.get("content", "").startswith("v=spf1"):
        return True
    if record.get("type") == "TXT" and relative_name == "_dmarc" and isinstance(record.get("content"), str) and record.get("content", "").startswith("v=DMARC1"):
        return True
    if record.get("type") in {"CNAME", "TXT"} and isinstance(relative_name, str) and "_domainkey" in relative_name:
        return True
    return False


def is_preview_record(record: dict[str, Any]) -> bool:
    return record.get("type") == "CNAME" and record.get("proxied") is True and isinstance(record.get("content"), str) and TUNNEL_TARGET_RE.match(record.get("content") or "") is not None


def _has_redirect_placeholder_pair(dns_records: list[dict[str, Any]], zone_name: str) -> bool:
    has_apex = any(
        is_apex_name(r.get("name"), zone_name) and r.get("type") == "A" and r.get("content") == "192.0.2.1"
        for r in dns_records
    )
    has_www = any(
        r.get("relative_name") == "www" and r.get("type") == "CNAME" and _strip_dot(r.get("content") or "") == _strip_dot(zone_name)
        for r in dns_records
    )
    return has_apex and has_www


def is_redirect_placeholder_record(record: dict[str, Any], zone_name: str) -> bool:
    if is_apex_name(record.get("name"), zone_name) and record.get("type") == "A" and record.get("content") == "192.0.2.1":
        return True
    if record.get("relative_name") == "www" and record.get("type") == "CNAME" and _strip_dot(record.get("content") or "") == _strip_dot(zone_name):
        return True
    return False


def _strip_dot(value: str) -> str:
    return value.rstrip(".")


def is_apex_name(name: str | None, zone_name: str) -> bool:
    if not name:
        return False
    return _strip_dot(name) in {_strip_dot(zone_name), "@"}


def nested_get(value: Any, *keys: str) -> Any:
    current = value
    for key in keys:
        if not isinstance(current, dict):
            return None
        current = current.get(key)
    return current


def module_instance_name(prefix: str, suffix: str) -> str:
    normalized = re.sub(r"[^a-zA-Z0-9]+", "_", suffix).strip("_").lower()
    return f"{prefix}_{normalized}" if normalized else prefix
