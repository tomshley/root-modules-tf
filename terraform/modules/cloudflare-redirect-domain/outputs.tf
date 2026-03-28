output "zone_id" {
  description = "Created Cloudflare zone ID for the redirect source domain."
  value       = cloudflare_zone.redirect.id
}

output "redirect_ruleset_id" {
  description = "Cloudflare Rulesets API ruleset ID that implements redirect behavior."
  value       = cloudflare_ruleset.redirect.id
}
