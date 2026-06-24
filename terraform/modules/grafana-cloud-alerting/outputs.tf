output "enabled" {
  description = "Whether the alert rules + contact point were deployed (enabled AND webhook_url set). False on cold-start / pre-webhook plans."
  value       = local.deploy
}

output "folder_uid" {
  description = "UID of the created Grafana folder (null when not deployed)."
  value       = local.deploy ? grafana_folder.this[0].uid : null
}

output "contact_point_name" {
  description = "Name of the webhook contact point (null when not deployed)."
  value       = local.deploy ? grafana_contact_point.webhook[0].name : null
}

output "metrics_rule_group" {
  description = "Name of the metric (pod-restart + OOMKilled) rule group (null when not deployed)."
  value       = local.deploy ? grafana_rule_group.metrics[0].name : null
}

output "logs_rule_group" {
  description = "Name of the log error rule group (null when the log rule is disabled or not deployed)."
  value       = local.deploy_logs ? grafana_rule_group.logs[0].name : null
}
