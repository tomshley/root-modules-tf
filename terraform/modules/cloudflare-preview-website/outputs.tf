output "tunnel_id" {
  description = "Cloudflare Tunnel ID for the preview tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.preview.id
}

output "tunnel_cname" {
  description = "Canonical tunnel CNAME target for the preview hostname."
  value       = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.preview.id)
}

output "preview_hostname" {
  description = "Preview hostname published by this module."
  value       = local.normalized_preview_hostname
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID for the preview hostname CNAME."
  value       = cloudflare_dns_record.preview.id
}
