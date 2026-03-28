output "mx_record_ids" {
  description = "Cloudflare DNS record IDs for MX records published by this module."
  value       = [for key in sort(keys(cloudflare_dns_record.mx)) : cloudflare_dns_record.mx[key].id]
}

output "spf_record_id" {
  description = "Cloudflare DNS record ID for the SPF TXT record."
  value       = cloudflare_dns_record.spf.id
}

output "dkim_record_ids" {
  description = "Cloudflare DNS record IDs for DKIM records published by this module."
  value       = [for key in sort(keys(cloudflare_dns_record.dkim)) : cloudflare_dns_record.dkim[key].id]
}

output "dmarc_record_id" {
  description = "Cloudflare DNS record ID for the DMARC TXT record."
  value       = cloudflare_dns_record.dmarc.id
}

output "verification_record_ids" {
  description = "Cloudflare DNS record IDs for verification TXT records published by this module."
  value       = [for key in sort(keys(cloudflare_dns_record.verification)) : cloudflare_dns_record.verification[key].id]
}
