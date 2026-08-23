output "issuer_url" {
  value       = local.issuer_url
  description = "Normalized issuer URL (https scheme, no trailing slash)."
}

output "issuer_host" {
  value       = local.issuer_host
  description = "Issuer with the scheme stripped, path segments preserved. The usual prefix for claim references in platform trust grammars."
}

output "audiences" {
  value       = var.audiences
  description = "Audiences as given. Empty means the implementation applies its platform-appropriate default."
}

output "conditions" {
  value       = local.conditions
  description = "Normalized trust conditions (claim, match = exact|wildcard, values)."
}

output "exact_conditions" {
  value       = local.exact_conditions
  description = "The subset of conditions with match = \"exact\"."
}

output "wildcard_conditions" {
  value       = local.wildcard_conditions
  description = "The subset of conditions with match = \"wildcard\". An implementation whose platform cannot express glob matching MUST fail on a non-empty value here rather than degrade the match."
}

output "trust" {
  value = {
    issuer_url  = local.issuer_url
    issuer_host = local.issuer_host
    audiences   = var.audiences
    conditions  = local.conditions
  }
  description = "The complete normalized trust object — the single input an implementation module consumes."
}
