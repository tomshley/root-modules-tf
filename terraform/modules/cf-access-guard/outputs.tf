output "access_application_id" {
  description = "Cloudflare Access application ID for the protected hostname."
  value       = cloudflare_zero_trust_access_application.guard.id
}

output "access_policy_id" {
  description = "Cloudflare Access inline policy ID for the protected hostname, or null until assigned by Cloudflare."
  value       = try(cloudflare_zero_trust_access_application.guard.policies[0].id, null)
}
