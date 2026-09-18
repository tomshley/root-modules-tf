output "workload_identity_pool_name" {
  value       = google_iam_workload_identity_pool.ci.name
  description = "Fully qualified name of the Workload Identity Pool (projects/{n}/locations/global/workloadIdentityPools/{id})."
}

output "workload_identity_provider_name" {
  value       = google_iam_workload_identity_pool_provider.ci.name
  description = "Fully qualified name of the OIDC workload identity provider — the value a CI platform uses for Workload Identity Federation."
}

output "service_account_email" {
  value       = google_service_account.ci_deploy.email
  description = "Email of the federated CI service account — the identity a pipeline impersonates."
}

output "service_account_id" {
  value       = google_service_account.ci_deploy.account_id
  description = "ID of the federated CI service account ({project_name_prefix}-ci-{role_name_suffix})."
}

output "issuer_host" {
  value       = module.trust.issuer_host
  description = "Normalized issuer host the trust conditions are keyed on."
}
