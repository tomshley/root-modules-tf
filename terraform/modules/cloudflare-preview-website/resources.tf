locals {
  normalized_zone_id          = trimspace(var.zone_id)
  normalized_account_id       = trimspace(var.account_id)
  normalized_tunnel_name      = trimspace(var.tunnel_name)
  normalized_tunnel_secret    = trimspace(var.tunnel_secret)
  normalized_preview_hostname = lower(trimspace(var.preview_hostname))
  normalized_origin_url       = trimspace(var.origin_url)
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "preview" {
  account_id    = local.normalized_account_id
  name          = local.normalized_tunnel_name
  config_src    = "cloudflare"
  tunnel_secret = local.normalized_tunnel_secret
}

resource "cloudflare_dns_record" "preview" {
  zone_id = local.normalized_zone_id
  name    = local.normalized_preview_hostname
  type    = "CNAME"
  ttl     = 1
  proxied = true
  content = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.preview.id)
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "preview" {
  account_id = local.normalized_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.preview.id

  config = {
    ingress = [
      {
        hostname = local.normalized_preview_hostname
        service  = local.normalized_origin_url
      },
      {
        service = "http_status:404"
      }
    ]
  }
}
