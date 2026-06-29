###############################################################################
# Grafana Cloud Alerting — Standalone Example
#
# Grafana-managed workload-health alert rules (pod restarts, OOMKilled, and an
# optional Loki error-log rule) plus caller-defined Prometheus/Loki rules,
# routed to a generic webhook contact point (incident.io / PagerDuty / Opsgenie
# / Slack-webhook / ...).
#
# Requires a `grafana` provider configured (url + auth token) against the
# target Grafana / Grafana Cloud instance. The datasource lookups run at plan
# time, so set enabled = false until the provider points at a real instance.
# Replace placeholder values before applying.
#
# By default the module stays inert until webhook_url is set. Set
# require_webhook = false (see the module block) to deploy and evaluate the
# rules BEFORE wiring a webhook — useful for validating rule expressions against
# live data; until a webhook_url is supplied the rules route to the org default
# notification policy.
###############################################################################

variable "namespace" {
  type    = string
  default = "example-workload"
}

variable "webhook_url" {
  type    = string
  default = "https://api.example.com/v2/alerts/REPLACE_WITH_YOUR_WEBHOOK_PATH"
}

variable "webhook_token" {
  type      = string
  sensitive = true
  default   = "REPLACE_WITH_YOUR_WEBHOOK_TOKEN"
}

variable "grafana_stack_slug" {
  type    = string
  default = "example-stack" # derives grafanacloud-<slug>-prom / -logs datasource names
}

module "alerting" {
  source = "../../modules/grafana-cloud-alerting"

  namespace          = var.namespace
  webhook_url        = var.webhook_url
  webhook_token      = var.webhook_token
  grafana_stack_slug = var.grafana_stack_slug

  # Default true keeps the whole module inert until a webhook destination
  # exists. Set false to render + evaluate the rules before webhook_url is
  # supplied (they route to the org default notification policy until then).
  require_webhook = true

  alert_labels = {
    team    = "platform"
    service = "example-workload"
  }

  # Custom Prometheus rules are appended after the pod-restart/OOM built-ins.
  metric_rules = [
    {
      # Saturation threshold: a "> N" alert.
      name         = "work queue backlog high"
      expr         = "sum(example_work_queue_depth)"
      threshold    = 1000
      for_duration = "10m"
      severity     = "warning"
      annotations = {
        summary     = "Work queue backlog above threshold in ${var.namespace}"
        description = "example_work_queue_depth exceeded 1000 for 10m."
      }
    },
    {
      # Compound no-progress signal: backlog present AND not draining. The 15m
      # range selector requires query_from_seconds >= 900.
      name               = "work queue not draining"
      expr               = "(sum(example_work_queue_depth) > 0) and (delta(sum(example_work_queue_depth)[15m:1m]) >= 0)"
      threshold          = 0
      query_from_seconds = 900
      for_duration       = "15m"
      severity           = "critical"
      annotations = {
        summary     = "Work queue not draining in ${var.namespace}"
        description = "Backlog present and flat/growing over 15m; processing appears stalled."
      }
    },
  ]

  # Custom Loki rules are appended after the optional error-log built-in.
  log_rules = [
    {
      name               = "elevated warning-log rate"
      expr               = "sum(count_over_time({namespace=\"${var.namespace}\"} |~ `(?i)warn` [10m]))"
      threshold          = 5
      query_from_seconds = 600
      for_duration       = "0s"
      severity           = "warning"
      annotations = {
        summary     = "Elevated warning-log rate in ${var.namespace}"
        description = "More than 5 warning log lines in the last 10m."
      }
    },
  ]
}

output "alerting_enabled" {
  value = module.alerting.enabled
}

output "alerting_notifications_enabled" {
  value = module.alerting.notifications_enabled
}

output "metrics_rule_group" {
  value = module.alerting.metrics_rule_group
}

output "metric_rule_names" {
  value = module.alerting.metric_rule_names
}

output "log_rule_names" {
  value = module.alerting.log_rule_names
}
