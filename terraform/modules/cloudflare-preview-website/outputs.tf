output "tunnel_id" {
  description = "Cloudflare Tunnel ID for the tunnel."
  value       = cloudflare_zero_trust_tunnel_cloudflared.preview.id
}

output "tunnel_cname" {
  description = "Canonical tunnel CNAME target shared by every published hostname."
  value       = format("%s.cfargotunnel.com", cloudflare_zero_trust_tunnel_cloudflared.preview.id)
}

output "preview_hostname" {
  description = "Hostname published through the legacy preview_hostname input, or null when unset."
  value       = local.normalized_preview_hostname
}

output "dns_record_id" {
  description = "Cloudflare DNS record ID for the preview_hostname CNAME, or null when preview_hostname is unset."
  value       = one(cloudflare_dns_record.preview[*].id)
}

output "hostnames" {
  description = "Every hostname published through the tunnel, sorted ascending."
  value       = sort([for e in local.all_entries : e.hostname])
}

output "dns_record_ids" {
  description = "Map of published hostname to Cloudflare DNS record ID, covering both preview_hostname and hostnames entries."
  value = merge(
    { for r in cloudflare_dns_record.preview : local.normalized_preview_hostname => r.id },
    { for hostname, r in cloudflare_dns_record.published : hostname => r.id },
  )
}

output "tunnel_token" {
  description = "Connector token for the tunnel, present only when expose_tunnel_token is true."
  value       = one(data.cloudflare_zero_trust_tunnel_cloudflared_token.this[*].token)
  sensitive   = true
}
