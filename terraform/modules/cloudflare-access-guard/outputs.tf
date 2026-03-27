output "access_application_id" {
  description = "Cloudflare Access application ID for the protected hostname."
  value       = cloudflare_zero_trust_access_application.guard.id
}
