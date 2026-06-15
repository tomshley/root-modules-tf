output "project_id" {
  description = "Cloudflare Pages project ID."
  value       = cloudflare_pages_project.this.id
}

output "project_name" {
  description = "Cloudflare Pages project name."
  value       = cloudflare_pages_project.this.name
}

output "project_subdomain" {
  description = "Default pages.dev subdomain for the project."
  value       = cloudflare_pages_project.this.subdomain
}

output "custom_domains" {
  description = "Custom domains attached to the project."
  value       = [for _, d in cloudflare_pages_domain.custom : d.name]
}

output "custom_domain_dns_record_ids" {
  description = "Cloudflare DNS record IDs for custom-domain CNAME records managed by this module."
  value       = { for hostname, record in cloudflare_dns_record.custom_domain_cname : hostname => record.id }
}
