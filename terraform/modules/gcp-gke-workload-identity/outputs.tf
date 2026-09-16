output "google_service_account_email" {
  value = google_service_account.workload.email
}

output "google_service_account_name" {
  value = google_service_account.workload.name
}

output "kubernetes_service_account_annotation" {
  value = {
    "iam.gke.io/gcp-service-account" = google_service_account.workload.email
  }
}

output "kubernetes_service_account_subject" {
  value = "system:serviceaccount:${var.namespace}:${var.kubernetes_service_account_name}"
}
