###############################################################################
# Grafana Cloud Alerting — Standalone Example
#
# Grafana-managed workload-health alert rules (pod restarts, OOMKilled, and an
# optional Loki error-log rule) routed to a generic webhook contact point
# (incident.io / PagerDuty / Opsgenie / Slack-webhook / ...).
#
# Requires a `grafana` provider configured (url + auth token) against the
# target Grafana / Grafana Cloud instance. The datasource lookups run at plan
# time, so set enabled = false until the provider points at a real instance.
# Replace placeholder values before applying.
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

  alert_labels = {
    team    = "platform"
    service = "example-workload"
  }
}

output "alerting_enabled" {
  value = module.alerting.enabled
}

output "metrics_rule_group" {
  value = module.alerting.metrics_rule_group
}
