output "network_id" {
  value = google_compute_network.gke_network.id
}

output "subnetwork_id" {
  value = google_compute_subnetwork.gke_subnet.id
}

output "subnetwork_region" {
  value = google_compute_subnetwork.gke_subnet.region
}

output "services_secondary_range_name" {
  value = google_compute_subnetwork.gke_subnet.secondary_ip_range[0].range_name
}

output "pods_secondary_range_name" {
  value = google_compute_subnetwork.gke_subnet.secondary_ip_range[1].range_name
}

output "private_services_connection_id" {
  value = google_service_networking_connection.private_services.id
}

output "node_network_tags" {
  value = var.node_network_tags
}

