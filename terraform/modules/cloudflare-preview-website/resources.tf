locals {
  normalized_zone_id          = var.zone_id == null ? null : trimspace(var.zone_id)
  normalized_account_id       = trimspace(var.account_id)
  normalized_tunnel_name      = trimspace(var.tunnel_name)
  normalized_tunnel_secret    = trimspace(var.tunnel_secret)
  normalized_preview_hostname = var.preview_hostname == null ? null : lower(trimspace(var.preview_hostname))
  normalized_origin_url       = var.origin_url == null ? null : trimspace(var.origin_url)

  legacy_entries = var.preview_hostname == null ? [] : [{
    hostname   = lower(trimspace(var.preview_hostname))
    zone_id    = trimspace(var.zone_id)
    origin_url = trimspace(var.origin_url)
  }]
  list_entries = [for h in var.hostnames : {
    hostname   = lower(trimspace(h.hostname))
    zone_id    = trimspace(h.zone_id)
    origin_url = trimspace(coalesce(h.origin_url, var.origin_url))
  }]
  all_entries = concat(local.legacy_entries, local.list_entries)

  # Ingress order is sorted by hostname for plan stability; the 404 catch-all
  # is always last. Hostnames are unique by validation, so the map is safe.
  entries_by_hostname = { for e in local.all_entries : e.hostname => e }
  sorted_entries      = [for h in sort(keys(local.entries_by_hostname)) : local.entries_by_hostname[h]]
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "preview" {
  account_id    = local.normalized_account_id
  name          = local.normalized_tunnel_name
  config_src    = "cloudflare"
  tunnel_secret = local.normalized_tunnel_secret
}

resource "cloudflare_dns_record" "preview" {
  count = var.preview_hostname == null ? 0 : 1

  zone_id = local.normalized_zone_id
  name    = local.normalized_preview_hostname
  type    = "CNAME"
  ttl     = 1
  proxied = true
  content = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.preview.id)
}

moved {
  from = cloudflare_dns_record.preview
  to   = cloudflare_dns_record.preview[0]
}

resource "cloudflare_dns_record" "published" {
  for_each = { for e in local.list_entries : e.hostname => e }

  zone_id = each.value.zone_id
  name    = each.value.hostname
  type    = "CNAME"
  ttl     = 1
  proxied = true
  content = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.preview.id)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "preview" {
  account_id = local.normalized_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.preview.id

  config = {
    ingress = concat(
      [for e in local.sorted_entries : {
        hostname = e.hostname
        service  = e.origin_url
      }],
      [
        {
          service = "http_status:404"
        }
      ]
    )
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "this" {
  count = var.expose_tunnel_token ? 1 : 0

  account_id = local.normalized_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.preview.id
}
