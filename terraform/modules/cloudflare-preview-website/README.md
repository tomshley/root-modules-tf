# cloudflare-preview-website

Publish a preview hostname backed by a Cloudflare Tunnel in an existing zone.

This module manages:
- A remotely managed Cloudflare Tunnel
- Tunnel configuration with a single ingress rule for the preview hostname
- A proxied preview hostname CNAME pointing to `<tunnel_id>.cfargotunnel.com`

This module does not create a zone, manage Access policies, manage cache rules, manage public website acceleration, or manage mail DNS.

## Inputs

- `zone_id`
  - Existing Cloudflare zone ID where the preview hostname will be published.
- `account_id`
  - Cloudflare account ID that owns the tunnel.
- `tunnel_name`
  - Display name for the Cloudflare Tunnel.
- `tunnel_secret`
  - Caller-provided tunnel secret.
- `preview_hostname`
  - Preview hostname to publish, for example `preview.example.com`.
- `origin_url`
  - Origin URL that cloudflared should proxy to, for example `http://localhost:8080`.

## Cloudflare API surface

Implemented with the Cloudflare v5 provider using:
- `cloudflare_zero_trust_tunnel_cloudflared`
- `cloudflare_zero_trust_tunnel_cloudflared_config`
- `cloudflare_dns_record`

## Outputs

- `tunnel_id`
  - Cloudflare Tunnel ID.
- `tunnel_cname`
  - Canonical tunnel target in the form `<tunnel_id>.cfargotunnel.com`.
- `preview_hostname`
  - Published preview hostname.
- `dns_record_id`
  - Cloudflare DNS record ID for the preview CNAME.

## Notes

- This module is limited to preview publication only: tunnel, tunnel config, and preview DNS.
- Access control is intentionally separate and should be composed with `cloudflare-access-guard` when preview access must be restricted.
- This module does not own cache rules.
- The tunnel configuration always includes a final `http_status:404` catch-all ingress rule.
