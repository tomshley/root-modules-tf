output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.karpenter.name
}

output "release_namespace" {
  description = "Namespace of the Helm release"
  value       = helm_release.karpenter.namespace
}

output "release_version" {
  description = "Chart version of the Helm release"
  value       = helm_release.karpenter.version
}

output "release_status" {
  description = "Status of the Helm release"
  value       = helm_release.karpenter.status
}
