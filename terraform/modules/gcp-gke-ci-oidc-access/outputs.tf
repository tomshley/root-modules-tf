output "workload_identity_pool_name" {
  description = "Full resource name of the Workload Identity Pool (includes project number)"
  value       = google_iam_workload_identity_pool.ci.name
}

output "workload_identity_provider_name" {
  description = "Full resource name of the Workload Identity Provider"
  value       = google_iam_workload_identity_pool_provider.ci.name
}

output "service_account_email" {
  description = "Email of the created service account"
  value       = google_service_account.ci_deploy.email
}

output "service_account_id" {
  description = "Account ID of the created service account"
  value       = google_service_account.ci_deploy.account_id
}
