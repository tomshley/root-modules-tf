# cf-access-guard

Protect an existing hostname with Cloudflare Access using email and email-domain allow rules.

This module manages:
- A Cloudflare Access application for a self-hosted hostname
- An inline Cloudflare Access policy with email and email-domain include rules
- Session duration configuration on the Access application

This module does not create a zone, manage DNS records, manage tunnel configuration, manage cache behavior, or manage mail DNS.

## Inputs

- `zone_id`
  - Existing Cloudflare zone ID for the protected hostname.
- `account_id`
  - Cloudflare account ID that owns the Access policy.
- `hostname`
  - Hostname to protect, for example `preview.example.com`.
- `application_name`
  - Display name for the Access application.
- `allowed_emails`
  - Default: `[]`
  - Explicit email addresses allowed by the Access policy.
- `allowed_email_domains`
  - Default: `[]`
  - Email domains allowed by the Access policy.
- `session_duration`
  - Default: `"24h"`
  - Session duration applied to the Access application.

## Allow-rule validation

This module normalizes both `allowed_emails` and `allowed_email_domains` by trimming whitespace, dropping empty values, and de-duplicating entries.

A lifecycle precondition on the Access application enforces that at least one normalized allow list is non-empty before Terraform can plan or apply the module.

## Cloudflare API surface

Implemented with the Cloudflare v5 provider using:
- `cloudflare_zero_trust_access_application`

## Outputs

- `access_application_id`
  - Cloudflare Access application ID.

## Notes

- This module assumes the protected hostname already resolves in DNS.
- The allow policy is defined inline on the Access application to avoid the reusable-policy attachment path exposed by the Cloudflare v5 provider.
- The Cloudflare v5 provider does not expose a stable standalone ID for the inline policy block, so this module intentionally outputs only the Access application ID.
- This module does not own any tunnel, DNS, or cache configuration.
