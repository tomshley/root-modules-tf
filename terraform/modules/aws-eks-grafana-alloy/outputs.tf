output "enabled" {
  description = "Whether the k8s-monitoring release was actually deployed (passed both the enabled switch and the endpoint + credential readiness gate). False on cold-start / pre-credential plans."
  value       = local.release_ready
}

output "namespace" {
  description = "Namespace the collectors were deployed into (null when not deployed)."
  value       = local.release_ready ? var.namespace : null
}

output "release_name" {
  description = "Name of the Helm release (null when not deployed)."
  value       = local.release_ready ? helm_release.k8s_monitoring[0].name : null
}

output "credential_source" {
  description = "Which credential path is in effect: \"secret\" (pre-existing Kubernetes Secret, no token in state), \"inline\" (token embedded in chart values + state), or \"none\" (release inert)."
  value       = local.release_ready ? (local.use_secret_ref ? "secret" : "inline") : "none"
}

output "chart_version" {
  description = "Pinned k8s-monitoring Helm chart version."
  value       = var.chart_version
}
