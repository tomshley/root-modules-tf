
output "google_container_cluster_default" {
  value = google_container_cluster.default
}

output "google_container_cluster_default_name" {
  value = google_container_cluster.default.name
}

output "google_service_account_default" {
  value = google_service_account.default
}

output "google_service_account_default_account_id" {
  value = google_service_account.default.account_id
}