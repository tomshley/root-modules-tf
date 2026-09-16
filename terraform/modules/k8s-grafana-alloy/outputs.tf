output "enabled" { value = local.release_ready }
output "namespace" { value = local.release_ready ? var.namespace : null }
output "release_name" { value = local.release_ready ? helm_release.k8s_monitoring[0].name : null }
output "credential_source" { value = local.release_ready ? (local.use_secret_ref ? "secret" : "inline") : "none" }
output "chart_version" { value = var.chart_version }
