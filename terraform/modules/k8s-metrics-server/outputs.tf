output "release_name" {
  value = helm_release.metrics_server.name
}

output "release_namespace" {
  value = helm_release.metrics_server.namespace
}

output "release_version" {
  value = helm_release.metrics_server.version
}

output "release_status" {
  value = helm_release.metrics_server.status
}
