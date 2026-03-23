# cf-redirect-domain

Run a domain purely as an SEO-safe redirect to a canonical destination, owning its own Cloudflare zone lifecycle.

This module manages:
- Unconditional Cloudflare zone creation
- A proxied placeholder apex A record using `192.0.2.1`
- A proxied `www` CNAME record pointing to the apex
- A zone-scoped Single Redirect rule covering both apex and `www` hosts

This module does not manage the destination domain, caching, mail DNS, access policies, tunnel configuration, or Page Rules.

## Inputs

- `zone_name`
  - Redirect source domain.
  - Required.
- `account_id`
  - Cloudflare account ID.
  - Required.
- `redirect_target`
  - Canonical destination host.
  - Required.
  - Provide only the host name, not a full URL.
- `redirect_code`
  - Default: `301`
  - Allowed values: `301`, `302`
- `preserve_path`
  - Default: `true`
- `preserve_query`
  - Default: `true`

## Redirect implementation shape

This module follows the frozen architecture pattern:
- create the zone unconditionally with `account_id`
- create a proxied placeholder apex A record with `192.0.2.1`
- create a proxied `www` CNAME pointing to the apex
- create a zone-scoped `cloudflare_ruleset` in `http_request_dynamic_redirect`

The redirect rule is configured as:
- match expression: `(http.host eq "<zone_name>" or http.host eq "www.<zone_name>")`
- status code: from `redirect_code`
- query preservation: mapped from `preserve_query`
- target URL expression:
  - `concat("https://<redirect_target>", http.request.uri.path)` when `preserve_path = true`
  - `"https://<redirect_target>/"` when `preserve_path = false`

This gives whole-domain redirect behavior while preserving optional path and query behavior.

Path preservation and query preservation are handled by separate Cloudflare redirect fields in this module. `preserve_path` changes only the `target_url.expression`, while `preserve_query` maps to `preserve_query_string` on the redirect action.

## Cloudflare API surface

Implemented with the Cloudflare v5 provider using:
- `cloudflare_zone`
- `cloudflare_dns_record`
- `cloudflare_ruleset` in phase `http_request_dynamic_redirect`

## Outputs

- `zone_id`
  - Created Cloudflare zone ID.
- `redirect_rule_id`
  - Redirect rule ID from the created ruleset.

## Notes

- The placeholder apex A record and `www` CNAME are both proxied so that Cloudflare handles redirect traffic for both hosts.
- `redirect_target` must be the final canonical destination host, not an intermediate that redirects again.
- This module intentionally does not manage mail behavior. If the legacy domain must keep receiving mail, compose `cf-mail-foundation` using the `zone_id` output.
