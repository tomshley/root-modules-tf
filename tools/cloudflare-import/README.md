# cloudflare-import

`tools/cloudflare-import/` is a real read-only Cloudflare migration utility for the Cloudflare module set implemented in this repository.

## Purpose

The utility inventories an existing Cloudflare account and/or selected zones, normalizes the raw API data into stable internal structures, classifies discovered state into the approved `cloudflare-*` module model, and emits review-oriented Terraform scaffolding plus summary artifacts.

It is intentionally migration-focused and review-oriented. It does not mutate Cloudflare resources and it does not attempt automatic state import or automatic apply.

## Implemented CLI

The entrypoint is:

```bash
python3 tools/cloudflare-import/main.py --help
```

Implemented subcommands:

- `inventory`
  - fetch raw read-only Cloudflare inventory and write `inventory/raw_inventory.json`
- `run`
  - fetch inventory and then run normalize, classify, scaffold, and review outputs
- `replay`
  - rerun normalize, classify, scaffold, and review from a previously saved inventory JSON file

## Live usage

Using an environment variable for the read-only Cloudflare token:

```bash
export CLOUDFLARE_API_TOKEN="..."

python3 tools/cloudflare-import/main.py run \
  --account-id <cloudflare-account-id> \
  --output-dir /tmp/cloudflare-import-output
```

Zone-targeted usage:

```bash
export CLOUDFLARE_API_TOKEN="..."

python3 tools/cloudflare-import/main.py run \
  --zone-id <zone-id-1> \
  --zone-id <zone-id-2> \
  --output-dir /tmp/cloudflare-import-output
```

Replay usage with the included sample fixture:

```bash
python3 tools/cloudflare-import/main.py replay \
  --input tools/cloudflare-import/examples/sample_inventory.json \
  --output-dir /tmp/cloudflare-import-smoke
```

## Implemented phases

1. Inventory
   - enumerates zones
   - enumerates DNS records
   - enumerates zone rulesets
   - reads SSL/TLS and website-related zone settings used by the implemented modules
   - enumerates account tunnels when `account_id` is supplied
   - attempts to read tunnel configurations for ingress hostname/service recovery
   - enumerates Access applications and preserves embedded policy data when present
2. Normalize
   - converts raw API responses into stable per-zone and per-account structures
   - normalizes DNS record names into both FQDN and relative-name forms
   - normalizes tunnel ingress and Access application policy shapes
3. Classify
   - classifies likely `cloudflare-domain-baseline`
   - classifies likely `cloudflare-mail-foundation`
   - classifies likely `cloudflare-website-acceleration`
   - classifies likely `cloudflare-preview-website`
   - classifies likely `cloudflare-access-guard`
   - classifies likely `cloudflare-redirect-domain`
   - marks uncertain reconstruction with `review_required`
4. Scaffold
   - emits per-zone `main.tf` scaffold files using the implemented module set in `terraform/modules/`
   - preserves discovered safe values where possible
   - uses explicit placeholder values such as `REVIEW_REQUIRED_*` when exact safe reconstruction is not possible
5. Review package
   - emits machine-readable inventory and classification outputs
   - emits human-readable `review_summary.md`
   - emits human-readable `import_hints.md`
   - emits a scaffold manifest

## Output artifacts

Given `--output-dir /tmp/cloudflare-import-output`, the utility writes:

- `inventory/raw_inventory.json`
- `inventory/normalized_inventory.json`
- `classification/classifications.json`
- `review/review_summary.md`
- `review/import_hints.md`
- `scaffold/<zone-slug>/main.tf`
- `scaffold/manifest.json`

## Classification model

Implemented heuristics are aligned to the module contracts in this repo:

- `cloudflare-domain-baseline`
  - existing-zone SSL/TLS posture plus curated non-mail DNS records
- `cloudflare-mail-foundation`
  - MX, SPF, DKIM, DMARC, and provider-verification TXT indicators
- `cloudflare-website-acceleration`
  - HTTPS enforcement, HSTS, Brotli/Polish/Mirage/Early Hints/Bot Fight mode, cache rulesets, and canonical redirect rulesets
- `cloudflare-preview-website`
  - proxied CNAME records targeting `*.cfargotunnel.com`, optionally joined to discovered tunnel inventory and ingress configuration
- `cloudflare-access-guard`
  - self-hosted Access applications and recoverable email/email-domain policy includes
- `cloudflare-redirect-domain`
  - redirect-only zone pattern with proxied apex placeholder A record, proxied `www` CNAME, and zone-scoped redirect ruleset

## Important constraints

- read-only against Cloudflare
- no Cloudflare mutation
- no `terraform apply`
- no automatic state import
- no secret generation
- no force-fitting of unknown patterns into modules
- unknown or partial reconstruction is surfaced as review-required output

## Current MVP limitations

- Origin CA requests are not reconstructed
- Tunnel secrets are never recoverable and are always scaffolded as placeholders
- Access application recovery depends on the API response exposing policy include data
- Some Cloudflare account-level and non-module features are intentionally left as unclassified review items
- When scaffold output is written outside the repo, local module sources are emitted as absolute paths for clarity

## Dependencies

The MVP uses only the Python standard library. No additional dependency file is required.
