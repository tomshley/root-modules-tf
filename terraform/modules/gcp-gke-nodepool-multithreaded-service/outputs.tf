
output "google_container_cluster_default_multithreaded_service_pool" {
  value = google_container_node_pool.containerized-multithreaded-service-pool
}

output "google_container_cluster_default_multithreaded_service_pool_name" {
  value = google_container_node_pool.containerized-multithreaded-service-pool.name
}