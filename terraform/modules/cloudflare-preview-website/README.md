# cloudflare-preview-website

Publish one or more hostnames through a single Cloudflare Tunnel. Despite its
name, the module is not preview-specific: it creates the tunnel, its ingress
rules, and the DNS records for any set of hostnames, and leaves tunnel naming,
the cloudflared connector deployment, and access policy to the caller.

This module manages:
- A remotely managed Cloudflare Tunnel
- Tunnel configuration with one ingress rule per published hostname, sorted by
  hostname, plus a final `http_status:404` catch-all
- A proxied CNAME per hostname pointing to `<tunnel_id>.cfargotunnel.com`

This module does not create a zone, manage Access policies, manage cache rules, manage public website acceleration, or manage mail DNS.

## Inputs

Requires OpenTofu or Terraform 1.9 or later: the input validations cross-reference `preview_hostname`.

- `zone_id`
  - Existing Cloudflare zone ID where `preview_hostname` is published. Optional
    on its own; required when `preview_hostname` is set. `hostnames` entries
    carry their own `zone_id`.
- `account_id`
  - Cloudflare account ID that owns the tunnel.
- `tunnel_name`
  - Display name for the Cloudflare Tunnel.
- `tunnel_secret`
  - Caller-provided tunnel secret.
- `preview_hostname`
  - Single hostname to publish, for example `preview.example.com`. Optional;
    at least one of `preview_hostname` or `hostnames` must be supplied.
- `origin_url`
  - Origin URL that cloudflared should proxy to, for example
    `http://localhost:8080`. Required when `preview_hostname` is set; also the
    default origin for `hostnames` entries that omit their own.
- `hostnames`
  - Additional hostnames published through the same tunnel. Each entry takes
    `hostname`, `zone_id`, and an optional per-hostname `origin_url` override
    which, when supplied, must be a non-empty `http://` or `https://` URL;
    entries that omit it use the module-level `origin_url`, which is then
    required. Entries may live in different zones; hostnames must be unique
    across `preview_hostname` and the list. Every record is proxied — a
    `cfargotunnel.com` target only resolves through Cloudflare's proxy.
- `manage_dns_records`
  - Whether this module owns the DNS records for its published hostnames.
    Default `true`. Set `false` when another module owns the records — the
    ingress rules are still configured, because ingress membership and DNS
    ownership are separate concerns: a tunnel must be live and healthy before
    DNS is repointed to it, so staged cutovers run this module with
    `manage_dns_records = false` while another module keeps owning every
    record. Flipping an existing deployment from `true` to `false` plans a
    destroy of every record this module created. To hand live records to
    another owner without an outage, first forget them from this state
    without touching Cloudflare —
    `tofu state rm 'module.<name>.cloudflare_dns_record.preview' 'module.<name>.cloudflare_dns_record.published'`
    — then flip the flag (the plan now reports no changes for the records),
    and have the new owner adopt them with `import` blocks. A `removed` block
    cannot express this hand-off: the resource blocks stay declared in the
    module at zero instances, and `removed` is rejected while the block exists.
- `expose_tunnel_token`
  - When `true`, read the connector token through the
    `cloudflare_zero_trust_tunnel_cloudflared_token` data source and expose it
    as the `tunnel_token` output. Default `false`; the data source requires
    **Cloudflare Tunnel Write** permission on the API token, so existing
    consumers keep working with read-scoped credentials.

## Cloudflare API surface

Implemented with the Cloudflare v5 provider using:
- `cloudflare_zero_trust_tunnel_cloudflared`
- `cloudflare_zero_trust_tunnel_cloudflared_config`
- `cloudflare_zero_trust_tunnel_cloudflared_token` (data source, opt-in)
- `cloudflare_dns_record`

## Outputs

- `tunnel_id`
  - Cloudflare Tunnel ID.
- `tunnel_cname`
  - Canonical tunnel target in the form `<tunnel_id>.cfargotunnel.com`.
- `preview_hostname`
  - Hostname published through `preview_hostname`, or null when unset.
- `dns_record_id`
  - Cloudflare DNS record ID for the `preview_hostname` CNAME; null when
    `preview_hostname` is unset or `manage_dns_records` is `false`.
- `hostnames`
  - Every published hostname, sorted ascending.
- `dns_record_ids`
  - Map of hostname to DNS record ID covering both `preview_hostname` and
    `hostnames` entries. Empty when `manage_dns_records` is `false`.
- `tunnel_token`
  - Connector token, sensitive, present only when `expose_tunnel_token` is set.

## Notes

- One tunnel serves every published hostname: the ingress rules are the
  routing table and the DNS records share one `<tunnel_id>.cfargotunnel.com`
  target.
- A consumer passing only `preview_hostname` gets byte-identical resources to
  earlier releases: the legacy record moves to `cloudflare_dns_record.preview[0]`
  through a `moved` block, so existing state re-plans to zero changes.
- `manage_dns_records = false` on a fresh deployment never creates records;
  on an existing one it destroys them unless they were first removed from
  state — see the input description for the ownership-transfer sequence.
- Access control is intentionally separate and should be composed with `cloudflare-access-guard` when published hostnames must be restricted.
- This module does not own cache rules.
