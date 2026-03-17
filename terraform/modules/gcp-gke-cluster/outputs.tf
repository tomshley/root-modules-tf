output "google_project_id" {
  value = var.google_project_id
}

output "google_project_name_prefix" {
  value = var.project_name_prefix
}

output "google_compute_network_gke_network_id" {
  value = google_compute_network.gke_network.id
}

output "google_container_cluster_gke_cluster_name" {
  value = google_container_cluster.gke_cluster.name
}

output "google_service_account_gke_service_account_id" {
  value = google_service_account.gke_service_account.account_id
}

output "google_compute_subnetwork_region" {
  value = google_compute_subnetwork.gke_subnet.region
}

output "google_compute_subnetwork_id" {
  value = google_compute_subnetwork.gke_subnet.id
}

output "google_container_cluster_gke_cluster_self_link" {
  value = google_container_cluster.gke_cluster.self_link
}

output "google_container_cluster_gke_cluster_location" {
  value = google_container_cluster.gke_cluster.location
}

output "google_container_cluster_gke_cluster_endpoint" {
  value = google_container_cluster.gke_cluster.endpoint
}

output "google_container_cluster_gke_cluster_ca_certificate" {
  value     = google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "google_service_account_gke_service_account_email" {
  value = google_service_account.gke_service_account.email
}
