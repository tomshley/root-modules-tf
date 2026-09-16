output "release_name" {
  description = "Name of the Helm release"
  value       = module.metrics_server.release_name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = module.metrics_server.release_namespace
}

output "release_version" {
  description = "Chart version of the Helm release"
  value       = module.metrics_server.release_version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = module.metrics_server.release_status
}
