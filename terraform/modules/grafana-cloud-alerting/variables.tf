variable "enabled" {
  description = "Master switch. The rules are ALSO gated on webhook_url being set, so leaving this true keeps everything inert (count = 0) until the webhook is supplied. IMPORTANT: the caller must pass false whenever the grafana provider is not yet pointed at a real instance (url + token), otherwise the datasource lookups fail at plan — fold your provider-readiness check into this input."
  type        = bool
  default     = true
}

# --- Grafana objects ---

variable "folder_title" {
  description = "Title of the Grafana folder that will hold the alert rules."
  type        = string
  default     = "Workload Health Alerts"
}

variable "rule_group_name" {
  description = "Base name for the alert rule groups. The metric rules use this name; the log rule group uses \"<name>-logs\"."
  type        = string
  default     = "workload-health"
}

variable "evaluation_interval_seconds" {
  description = "How often (seconds) Grafana evaluates the rule groups."
  type        = number
  default     = 60
}

variable "namespace" {
  description = "Kubernetes namespace of the workload to watch. Interpolated into the PromQL/LogQL selectors (namespace=\"...\")."
  type        = string
}

# --- Datasource resolution ---

variable "prometheus_datasource_name" {
  description = "Name of the Prometheus datasource in Grafana. When null, falls back to the Grafana Cloud auto-provisioned name derived from grafana_stack_slug (grafanacloud-<slug>-prom), or \"grafanacloud-prom\" if the slug is also null."
  type        = string
  default     = null
}

variable "loki_datasource_name" {
  description = "Name of the Loki datasource in Grafana. When null, falls back to grafanacloud-<slug>-logs (or \"grafanacloud-logs\"). Only used when error_log_alert_enabled = true."
  type        = string
  default     = null
}

variable "grafana_stack_slug" {
  description = "Grafana Cloud stack slug, used only to derive the default Grafana Cloud datasource names. Leave null and set the *_datasource_name variables directly for self-hosted Grafana."
  type        = string
  default     = null
}

# --- Webhook contact point (vendor-neutral: incident.io / PagerDuty / Opsgenie / etc.) ---

variable "webhook_url" {
  description = "Webhook URL of the external alerting/on-call system that should receive notifications. Required for the module to deploy (the deploy gate). The contact point posts the Grafana alert payload here."
  type        = string
  default     = null
}

variable "webhook_token" {
  description = "Optional bearer credential for the webhook (e.g. an incident.io alert-source token). When null, no Authorization header is sent."
  type        = string
  default     = null
  sensitive   = true
}

variable "contact_point_name" {
  description = "Name of the Grafana contact point created for the webhook."
  type        = string
  default     = "alerts-webhook"
}

variable "webhook_http_method" {
  description = "HTTP method the contact point uses to call the webhook."
  type        = string
  default     = "POST"
}

variable "webhook_authorization_scheme" {
  description = "Authorization scheme paired with webhook_token (e.g. Bearer). Ignored when webhook_token is null."
  type        = string
  default     = "Bearer"
}

variable "notification_group_by" {
  description = "Alert grouping keys for the per-rule simplified notification routing (Grafana 10.4+)."
  type        = list(string)
  default     = ["alertname", "grafana_folder"]
}

# --- Labels + severities ---

variable "alert_labels" {
  description = "Labels merged into EVERY rule (e.g. { team = \"...\", service = \"...\" }). A per-rule severity label is added on top via the *_severity variables and wins on the \"severity\" key."
  type        = map(string)
  default     = {}
}

variable "pod_restart_severity" {
  description = "Value of the severity label on the pod-restart rule."
  type        = string
  default     = "critical"
}

variable "oom_severity" {
  description = "Value of the severity label on the OOMKilled rule."
  type        = string
  default     = "critical"
}

variable "error_log_severity" {
  description = "Value of the severity label on the error-log rule."
  type        = string
  default     = "warning"
}

# --- Per-rule tuning ---

variable "pod_restart_rule_name" {
  description = "Display name of the pod-restart alert rule (shown in Grafana / the alert payload). Scope it to the workload when running multiple instances of this module, e.g. \"<service> pod restarting\"."
  type        = string
  default     = "pod restarting"
}

variable "oom_rule_name" {
  description = "Display name of the OOMKilled alert rule."
  type        = string
  default     = "container OOMKilled"
}

variable "error_log_rule_name" {
  description = "Display name of the error-log alert rule."
  type        = string
  default     = "error logs detected"
}

variable "pod_restart_for" {
  description = "Pending period before the pod-restart alert fires."
  type        = string
  default     = "5m"
}

variable "error_log_for" {
  description = "Pending period before the error-log alert fires."
  type        = string
  default     = "5m"
}

variable "error_log_alert_enabled" {
  description = "Whether to create the Loki error-log rule group. Set false for workloads whose logs are not shipped to Loki — the two metric rules (pod restart, OOMKilled) still deploy."
  type        = bool
  default     = true
}

variable "error_log_pattern" {
  description = "LogQL line-filter regex for the error-log rule. Default targets connection/pool/availability failures (the 'trouble before crash' signal) and is intentionally framework-agnostic. Override with selectors specific to your stack."
  type        = string
  default     = "(?i)(acquire.*timed out|pool.*exhaust|connection.*(refused|reset|not.*available)|could not connect)"
}

variable "pod_restart_annotations" {
  description = "Annotations merged OVER the module's default summary/description for the pod-restart rule. Use to inject stack-specific runbook hints."
  type        = map(string)
  default     = {}
}

variable "oom_annotations" {
  description = "Annotations merged OVER the module's default summary/description for the OOMKilled rule."
  type        = map(string)
  default     = {}
}

variable "error_log_annotations" {
  description = "Annotations merged OVER the module's default summary/description for the error-log rule."
  type        = map(string)
  default     = {}
}
