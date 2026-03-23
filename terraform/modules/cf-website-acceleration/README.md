# cf-website-acceleration

Apply opinionated public website edge behavior to an existing Cloudflare zone.

This module manages:
- HTTPS enforcement
- HSTS
- Canonical host redirects
- Profile-based cache rules for static and immutable assets
- Brotli compression
- Optional Polish, Mirage, and Early Hints
- Optional Bot Fight Mode

This module does not create a zone, manage DNS identity, manage mail DNS, or use Page Rules.

## Inputs

- `zone_id`
  - Existing Cloudflare zone ID.
- `performance_profile`
  - Default: `standard`
  - Allowed values: `standard`, `aggressive`
- `canonical_redirect`
  - Default: `none`
  - Allowed values: `www-to-apex`, `apex-to-www`, `none`
- `enable_bot_fight_mode`
  - Default: `false`
- `edge_ttl_static`
  - Optional override for static asset edge TTL.
- `browser_ttl_static`
  - Optional override for static asset browser TTL.
- `edge_ttl_immutable`
  - Optional override for immutable asset edge TTL.
- `browser_ttl_immutable`
  - Optional override for immutable asset browser TTL.
- `enable_brotli`
  - Optional override.
- `enable_polish`
  - Optional override.
  - Allowed values: `off`, `lossless`, `lossy`
- `enable_mirage`
  - Optional override.
- `enable_early_hints`
  - Optional override.
- `hsts_max_age`
  - Default: `31536000`
- `hsts_include_subdomains`
  - Default: `true`
- `hsts_preload`
  - Default: `false`

## Profile resolution

`performance_profile` resolves in `locals.tf` to concrete values for:
- static asset edge/browser TTLs
- immutable asset edge/browser TTLs
- Brotli
- Polish
- Mirage
- Early Hints

Flat optional override variables win over the selected profile values when set.

Profiles:
- `standard`
  - Static assets: edge `14400`, browser `3600`
  - Immutable assets: edge `2592000`, browser `604800`
  - Brotli `on`, Polish `off`, Mirage `off`, Early Hints `off`
- `aggressive`
  - Static assets: edge `2592000`, browser `604800`
  - Immutable assets: edge `31536000`, browser `31536000`
  - Brotli `on`, Polish `lossless`, Mirage `on`, Early Hints `on`

## Cloudflare plan requirements

`polish`, `mirage`, and `early_hints` depend on Cloudflare plan level. The `aggressive` profile enables all three by default, so Free-plan zones may need to stay on `standard` or explicitly override those settings off.

## Cloudflare API surface

Implemented with the Cloudflare v5 provider using:
- Rulesets API
  - cache rules in `http_request_cache_settings`
  - canonical redirects in `http_request_dynamic_redirect`
- Zone Settings
  - `always_use_https`
  - `security_header` for HSTS
  - `brotli`
  - `polish`
  - `mirage`
  - `early_hints`
  - `bot_fight_mode`

## Outputs

- `cache_ruleset_id`
  - Rulesets API ruleset ID for cache behavior.
- `redirect_ruleset_id`
  - Rulesets API ruleset ID for canonical redirect behavior, or `null` when `canonical_redirect = "none"`.

## Notes

- Cache rules target static assets by file extension: `css`, `js`, `svg`, `woff2`.
- Immutable asset caching targets fingerprinted file names with a hex hash segment.
- Canonical redirects derive the zone hostname from Cloudflare rule fields so the module stays `zone_id`-only.
- No redirect ruleset is created when `canonical_redirect = "none"`, which avoids taking ownership of the `http_request_dynamic_redirect` phase unnecessarily.
- When `canonical_redirect` is not `none`, this module takes ownership of the zone-scoped `http_request_dynamic_redirect` phase for the target zone. Do not compose it with another module or manual configuration that also manages that phase on the same zone.
- This module is independent of mail concerns.
