output "workload_identity_pool_name" {
  value = google_iam_workload_identity_pool.ci.name
}

output "workload_identity_provider_name" {
  value = google_iam_workload_identity_pool_provider.ci.name
}

output "service_account_email" {
  value = google_service_account.ci_deploy.email
}

output "service_account_id" {
  value = google_service_account.ci_deploy.account_id
}
