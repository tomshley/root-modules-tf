# cloudflare-pages-site

Provision a Cloudflare Pages project and attach custom domains.

This module manages:
- A Cloudflare Pages project (`cloudflare_pages_project`)
- One or more Pages custom domains (`cloudflare_pages_domain`)
- Optional DNS CNAME records pointing each custom domain to `<project>.pages.dev`

## Inputs

- `account_id`
  - Cloudflare account ID that owns the Pages project.
- `project_name`
  - Pages project name. Lowercase letters, digits, and hyphens; 1-58 characters; no leading or trailing hyphen.
- `production_branch`
  - Default: `main`
  - Branch treated as production by Pages.
- `build_config`
  - Default: `null`
  - Optional Pages build settings. Use `null` for direct-upload workflows (for example, CI uploads with Wrangler).
- `custom_domains`
  - Default: `[]`
  - List of custom-domain objects:
    - `hostname` (required)
    - `zone_id` (required when `create_dns_record = true`; holds the module-managed CNAME)
    - `create_dns_record` (optional, default `true`)
    - `proxied` (optional, default `true`)
    - `comment` (optional)
  - Hostnames must be unique across the list (case-insensitive).

## Outputs

- `project_id`
  - Cloudflare Pages project ID.
- `project_name`
  - Cloudflare Pages project name.
- `project_subdomain`
  - Default `*.pages.dev` subdomain.
- `custom_domains`
  - List of attached custom domains.
- `custom_domain_dns_record_ids`
  - Map of custom-domain hostnames to DNS record IDs for module-managed CNAME records.

## Notes

- If custom-domain DNS records are managed elsewhere, set `create_dns_record = false` per domain and keep only the `cloudflare_pages_domain` attachment in this module. `zone_id` may then be omitted for that domain.
- For apex domains, Cloudflare supports proxied CNAME flattening.
- This module does not manage Cloudflare Pages git integration (the provider's `source` / `deployment_configs`); it targets direct-upload workflows plus `build_config`. See the note in `resources.tf` for where to extend if git-driven builds are needed.
