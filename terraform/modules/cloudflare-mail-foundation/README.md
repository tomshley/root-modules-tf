# cloudflare-mail-foundation

Publish mail DNS records for an existing Cloudflare zone.

This module manages:
- MX records
- SPF TXT record
- DKIM records
- DMARC TXT record
- Optional provider verification TXT records

This module does not create a zone, provision mailboxes, or manage non-mail DNS.

This module is provider-agnostic. It is intended to work with mail providers such as Proton Mail, Microsoft 365 / Outlook, Google Workspace, and similar services by accepting explicit DNS inputs rather than embedding provider presets.

## Inputs

- `zone_id`
  - Existing Cloudflare zone ID.
- `mx_records`
  - Required list of MX records.
  - Each item has `priority` and `value`.
- `spf_value`
  - Required SPF TXT value.
- `dkim_records`
  - Optional list of DKIM records.
  - Each item has `name`, `type`, and `value`.
  - Supported types: `CNAME`, `TXT`.
- `dmarc_value`
  - Required DMARC TXT value.
- `verification_records`
  - Optional list of TXT verification records.
  - Each item has `name` and `value`.

## Fixed record names

To stay aligned with the frozen architecture input contract, this module fixes the names of two records:
- SPF is published at the zone apex using `@`
- DMARC is published at `_dmarc`

MX records are also published at the zone apex using `@` because the architecture contract specifies only `priority` and `value` for `mx_records`.

## Composition boundary

When composing this module with `cloudflare-domain-baseline`, keep all mail-related DNS out of `cloudflare-domain-baseline.dns_records`. Duplicating SPF, DKIM, DMARC, MX, or verification TXT records across both modules can create invalid or misleading DNS state.

## Outputs

- `mx_record_ids`
  - List of Cloudflare DNS record IDs for MX records.
- `spf_record_id`
  - Cloudflare DNS record ID for the SPF TXT record.
- `dkim_record_ids`
  - List of Cloudflare DNS record IDs for DKIM records.
- `dmarc_record_id`
  - Cloudflare DNS record ID for the DMARC TXT record.

## Usage

```hcl
module "cloudflare_mail_foundation" {
  source = "../../modules/cloudflare-mail-foundation"

  zone_id = "cloudflare-zone-id"

  mx_records = [
    {
      priority = 1
      value    = "aspmx.l.google.com"
    },
    {
      priority = 5
      value    = "alt1.aspmx.l.google.com"
    }
  ]

  spf_value = "v=spf1 include:_spf.google.com ~all"

  dkim_records = [
    {
      name  = "google._domainkey"
      type  = "CNAME"
      value = "google._domainkey.example-provider.com"
    }
  ]

  dmarc_value = "v=DMARC1; p=reject; rua=mailto:dmarc@example.com"

  verification_records = [
    {
      name  = "google-site-verification"
      value = "verification-token"
    }
  ]
}
```
