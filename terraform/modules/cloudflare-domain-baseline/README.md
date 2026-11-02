# cloudflare-domain-baseline

Establish foundational Cloudflare posture for an existing zone.

This module manages:
- SSL/TLS mode
- Minimum TLS version
- Email address obfuscation toggle
- Curated DNS records limited to `A`, `AAAA`, `CNAME`, `TXT`, and `CAA`
- Optional Cloudflare Origin CA certificate issuance from a caller-provided CSR
- Optional custom error pages keyed by Cloudflare page identifier

This module does not create a zone.

## Inputs

- `zone_id`
  - Existing Cloudflare zone ID to configure.
- `ssl_mode`
  - Default: `strict`
  - Allowed values: `off`, `flexible`, `full`, `strict`
- `min_tls_version`
  - Default: `1.2`
  - Allowed values: `1.0`, `1.1`, `1.2`, `1.3`
- `email_obfuscation`
  - Default: `true`
  - Enables or disables Cloudflare Email Address Obfuscation for HTML responses
- `dns_records`
  - Default: `[]`
  - Curated baseline DNS records.
- `origin_ca`
  - Default: `null`
  - Optional Origin CA certificate request.
- `custom_error_pages`
  - Default: `{}`
  - Optional custom pages keyed by Cloudflare page identifier. Each value supplies `url` and optional `state` (`customized` by default). A null map uses the empty default. Requires a zone plan that includes custom error pages.

## DNS record contract

Supported record types are `A`, `AAAA`, `CNAME`, `TXT`, and `CAA`.

Each record may also carry an optional `comment`, passed through to the Cloudflare record.

Defaults:
- `ttl = 1`
- `proxied = true` for `A`, `AAAA`, and `CNAME` when omitted

Per-type field validity:

| Type | `value` | `proxied` | `caa` |
|---|---|---|---|
| `A` | Required IPv4 address | Optional | Must be omitted |
| `AAAA` | Required IPv6 address | Optional | Must be omitted |
| `CNAME` | Required target hostname | Optional | Must be omitted |
| `TXT` | Required text value | Must be omitted | Must be omitted |
| `CAA` | Must be omitted | Must be omitted | Required |

CAA payload shape:

```hcl
caa = {
  flags = 0
  tag   = "issue"
  value = "letsencrypt.org"
}
```

Supported CAA tags are `issue`, `issuewild`, and `iodef`.

The module validates the following constraints:
- Only supported record types are allowed.
- `ttl` must be `1` or between `60` and `86400`.
- `A` and `AAAA` records cannot share the same name as a `CNAME` record.
- Non-CAA records must set `value`.
- CAA records must omit `value` and instead provide `caa.flags`, `caa.tag`, and `caa.value`.

When composing with `cloudflare-mail-foundation`, keep mail DNS out of `dns_records`. In particular, do not define SPF, DKIM, DMARC, MX, or mail-provider verification records here when that companion module owns mail publication for the same zone.

`dns_records` are keyed internally by input order as well as record name and type. Reordering existing entries in the list changes the Terraform resource addresses and will cause record replacement even when the record contents stay the same.

When `origin_ca` is set, `requested_validity` must be one of Cloudflare's supported Origin CA validity periods: `7`, `30`, `90`, `365`, `730`, `1095`, or `5475` days.

`custom_error_pages` keys must be Cloudflare custom page identifiers: `500_errors`, `1000_errors`, `basic_challenge`, `country_challenge`, `ip_block`, `managed_challenge`, `ratelimit_block`, `under_attack`, `waf_block`, `waf_challenge`. For `state = "customized"`, `url` must be an HTTPS URL with a DNS hostname and no whitespace. For `state = "default"`, use `url = ""`. Custom error pages require a zone plan that includes them; entitlement and page acceptance are checked by Cloudflare when applied.

### Custom page lifecycle

The caller owns page content and hosting. Cloudflare fetches and stores the HTML; it does not fetch the URL for each visitor. The page must be publicly reachable when configured, meet the [HTML and size requirements](https://developers.cloudflare.com/rules/custom-errors/edit-error-pages/), and include the applicable [error tokens](https://developers.cloudflare.com/rules/custom-errors/reference/error-tokens/).

```hcl
custom_error_pages = {
  "500_errors" = {
    url = "https://static.example.com/errors/500.0123456789ab.html"
  }
}
```

To update content, publish a new versioned URL and change `url`. Changing bytes at the same URL produces no Terraform diff; Cloudflare requires an explicit re-fetch in that situation.

To retire a page, keep its key and first apply:

```hcl
custom_error_pages = {
  "500_errors" = { state = "default", url = "" }
}
```

Verify Cloudflare reports `state = "default"` before removing the key in a subsequent plan and apply. The [v5 provider's delete operation](https://github.com/cloudflare/terraform-provider-cloudflare/blob/v5.8.2/internal/services/custom_pages/resource.go) only removes Terraform state and does not reset Cloudflare. Removing a customized entry directly, including setting the map to `{}` or `null`, leaves its live page configured. Resetting at zone level can also expose an account-level custom page; inspect the effective page in the dashboard.

Omitting this input creates no custom-page resources and leaves existing page settings unmanaged. No page hosting, content upload, or account-level page management is performed by this module.

## Outputs

- `zone_id`
  - Configured Cloudflare zone ID.
- `dns_record_ids`
  - Map of deterministic record keys to Cloudflare DNS record IDs.
- `origin_ca_certificate`
  - Sensitive PEM-encoded Origin CA certificate when `origin_ca` is configured, otherwise `null`.

## Usage

```hcl
module "cloudflare_domain_baseline" {
  source = "../../modules/cloudflare-domain-baseline"

  zone_id           = "cloudflare-zone-id"
  ssl_mode          = "strict"
  min_tls_version   = "1.2"
  email_obfuscation = true

  dns_records = [
    {
      name  = "example.com"
      type  = "A"
      value = "198.51.100.10"
    },
    {
      name  = "www.example.com"
      type  = "CNAME"
      value = "example.com"
    },
    {
      name  = "example.com"
      type  = "CAA"
      caa = {
        flags = 0
        tag   = "issue"
        value = "letsencrypt.org"
      }
    }
  ]

  origin_ca = {
    csr = <<-EOT
-----BEGIN CERTIFICATE REQUEST-----
REPLACE_WITH_CSR
-----END CERTIFICATE REQUEST-----
EOT
    hostnames = ["example.com", "*.example.com"]
  }
}
```
