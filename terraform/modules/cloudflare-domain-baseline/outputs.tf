output "zone_id" {
  description = "Configured Cloudflare zone ID."
  value       = local.normalized_zone_id
}

output "dns_record_ids" {
  description = "Map of deterministic DNS record keys to Cloudflare DNS record IDs."
  value = merge(
    {
      for key, record in cloudflare_dns_record.standard : key => record.id
    },
    {
      for key, record in cloudflare_dns_record.txt : key => record.id
    },
    {
      for key, record in cloudflare_dns_record.caa : key => record.id
    }
  )
}

output "origin_ca_certificate" {
  description = "Origin CA certificate PEM when origin_ca is configured, otherwise null."
  value       = try(one([for certificate in cloudflare_origin_ca_certificate.this : certificate.certificate]), null)
  sensitive   = true
}
