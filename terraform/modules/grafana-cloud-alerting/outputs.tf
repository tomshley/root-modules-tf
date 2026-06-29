output "enabled" {
  description = "Whether the module's rules + folder were deployed. True once `enabled` is set and either webhook_url is set or require_webhook = false. False on cold-start / disabled plans."
  value       = local.deploy
}

output "notifications_enabled" {
  description = "Whether the webhook contact point exists and rules route to it (enabled AND webhook_url set). When false, any deployed rules route to the org default notification policy."
  value       = local.notify
}

output "folder_uid" {
  description = "UID of the created Grafana folder (null when not deployed)."
  value       = local.deploy ? grafana_folder.this[0].uid : null
}

output "contact_point_name" {
  description = "Name of the webhook contact point (null when no webhook_url is set, i.e. notifications route to the default policy)."
  value       = local.notify ? grafana_contact_point.webhook[0].name : null
}

output "metrics_rule_group" {
  description = "Name of the metric rule group (built-ins + metric_rules); null when no metric rule is effective or the module is not deployed."
  value       = local.deploy_metrics ? grafana_rule_group.metrics[0].name : null
}

output "logs_rule_group" {
  description = "Name of the log rule group (built-in error log + log_rules); null when no log rule is effective or the module is not deployed."
  value       = local.deploy_logs ? grafana_rule_group.logs[0].name : null
}

output "metric_rule_names" {
  description = "Display names of every effective metric rule, in render order; empty list when the group is not deployed."
  value       = local.deploy_metrics ? [for r in local.metric_rules_effective : r.name] : []
}

output "log_rule_names" {
  description = "Display names of every effective log rule, in render order; empty list when the group is not deployed."
  value       = local.deploy_logs ? [for r in local.log_rules_effective : r.name] : []
}
