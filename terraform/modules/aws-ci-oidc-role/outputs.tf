output "oidc_provider_arn" {
  value       = local.oidc_provider_arn
  description = "ARN of the IAM OIDC provider (existing or created)."
}

output "oidc_provider_created" {
  value       = local.create_oidc_provider
  description = "Whether this module created the provider (false when reusing an existing ARN)."
}

output "role_arn" {
  value       = aws_iam_role.ci.arn
  description = "ARN of the federated CI role."
}

output "role_name" {
  value       = aws_iam_role.ci.name
  description = "Name of the federated CI role."
}

output "issuer_host" {
  value       = module.trust.issuer_host
  description = "Normalized issuer host the trust conditions are keyed on."
}
