output "oidc_provider_arn" {
  value = local.oidc_provider_arn
}

output "oidc_provider_created" {
  value = local.create_oidc_provider
}

output "role_arn" {
  value = aws_iam_role.ci_deploy.arn
}

output "role_name" {
  value = aws_iam_role.ci_deploy.name
}
