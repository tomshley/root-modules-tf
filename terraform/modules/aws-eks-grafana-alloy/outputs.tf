output "enabled" {
  description = "Whether the k8s-monitoring release was actually deployed (passed both the enabled switch and the endpoint + credential readiness gate). False on cold-start / pre-credential plans."
  value       = module.alloy.enabled
}

output "namespace" {
  description = "Namespace the collectors were deployed into (null when not deployed)."
  value       = module.alloy.namespace
}

output "release_name" {
  description = "Name of the Helm release (null when not deployed)."
  value       = module.alloy.release_name
}

output "credential_source" {
  description = "Which credential path is in effect: \"secret\" (pre-existing Kubernetes Secret, no token in state), \"inline\" (token embedded in chart values + state), or \"none\" (release inert)."
  value       = module.alloy.credential_source
}

output "chart_version" {
  description = "Pinned k8s-monitoring Helm chart version."
  value       = module.alloy.chart_version
}
