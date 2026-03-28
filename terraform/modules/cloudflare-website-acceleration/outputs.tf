output "cache_ruleset_id" {
  description = "Cloudflare Rulesets API ruleset ID for cache behavior."
  value       = cloudflare_ruleset.cache.id
}

output "redirect_ruleset_id" {
  description = "Cloudflare Rulesets API ruleset ID for canonical redirect behavior, or null when canonical_redirect is none."
  value       = try(cloudflare_ruleset.redirect[0].id, null)
}
