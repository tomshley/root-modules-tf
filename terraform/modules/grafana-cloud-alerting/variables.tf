variable "enabled" {
  description = "Master switch / provider-readiness gate. When require_webhook is true (the default), the module ALSO stays inert (count = 0) until a webhook destination exists (webhook_url set, or webhook_configured = true); when require_webhook is false, the alert rules deploy as soon as this is true, regardless of the webhook. IMPORTANT: the caller must pass false whenever the grafana provider is not yet pointed at a real instance (url + token), otherwise the datasource lookups fail at plan — fold your provider-readiness check into this input."
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
  description = "Name of the Loki datasource in Grafana. When null, falls back to grafanacloud-<slug>-logs (or \"grafanacloud-logs\"). Only used when the built-in error-log rule or at least one log_rules entry is effective."
  type        = string
  default     = null
}

variable "grafana_stack_slug" {
  description = "Grafana Cloud stack slug, used only to derive the default Grafana Cloud datasource names. Leave null and set the *_datasource_name variables directly for self-hosted Grafana."
  type        = string
  default     = null
}

# --- Webhook contact point (vendor-neutral: incident.io / PagerDuty / Opsgenie / etc.) ---

variable "require_webhook" {
  description = "When true (default), the entire module stays inert (count = 0) until a webhook destination exists (webhook_url set, or webhook_configured = true), preserving the \"never create an alert rule without a delivery destination\" behavior. Set false to deploy and evaluate the rules as soon as enabled is true, BEFORE a webhook exists: the rules render in Grafana (showing Normal/Pending/Firing) and route via the org default notification policy until a destination is supplied, at which point the contact point is created and per-rule routing attaches to it. Lets you validate rule expressions against live data before wiring on-call."
  type        = bool
  default     = true
}

variable "webhook_url" {
  description = "Webhook URL of the external alerting/on-call system that should receive notifications. When require_webhook is true (default) this is also the module's deploy gate. The contact point posts the Grafana alert payload here; when null, no contact point is created and the rules (if require_webhook = false) route to the org default notification policy."
  type        = string
  default     = null
}

variable "webhook_configured" {
  description = "Plan-time-known override for \"a webhook destination exists\". REQUIRED when webhook_url/webhook_token come from another resource's attributes (e.g. the incident-io-alert-source module's alert_events_url/secret_token): those values are unknown until apply, so the default `webhook_url != null` gate cannot drive count and the plan fails with \"Invalid count argument\". Pass a bool derived from plan-time-known values only — e.g. `var.incident_io_api_key != null` or the source module's `enabled` input. Leave null (default) when webhook_url is a plain variable/literal."
  type        = bool
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
  description = "Labels merged into EVERY rule (e.g. { team = \"...\", service = \"...\" }). A per-rule severity label is added on top via the built-in *_severity variables or each custom rule's severity field and wins on the \"severity\" key."
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

# --- Built-in (house-default) metric rule toggles ---

variable "pod_restart_rule_enabled" {
  description = "Whether to emit the built-in pod-restart metric rule. Set false to drop this house default and rely solely on metric_rules."
  type        = bool
  default     = true
}

variable "oom_rule_enabled" {
  description = "Whether to emit the built-in OOMKilled metric rule. Set false to drop this house default and rely solely on metric_rules."
  type        = bool
  default     = true
}

# --- Generic caller-defined rules ---

variable "metric_rules" {
  description = <<-EOT
    Additional Prometheus-backed alert rules, appended to the metric rule group
    AFTER the built-in house defaults. Each rule fires when its query, reduced
    by `reducer`, is greater than `threshold`.

    Fields:
      - name          (required) Rule display name. Must be unique across the
                      effective metric set (built-ins + this list).
      - expr          (required) PromQL whose reduced value is compared to
                      `threshold`. Encode any condition that yields a series
                      only when breached, such as a saturation gauge or a
                      compound no-progress expression.
      - threshold     (optional, default 0) Fires when reduce(expr) > threshold.
      - reducer       (optional, default "last") last|max|min|mean|sum|count.
      - for_duration  (optional, default "5m") Pending period; maps to the
                      rule's Grafana `for`. Use "0s" to fire immediately.
      - severity      (optional, default "critical") Value of the `severity`
                      label, merged over alert_labels.
      - annotations   (optional, default {}) Annotation map (summary,
                      description, runbook_url, ...). Grafana templating allowed,
                      e.g. "{{ $labels.pod }}".
      - query_from_seconds (optional, default 600) relative_time_range lookback
                      in seconds. Must cover the largest range selector in
                      `expr`; a "[15m]" selector needs at least 900.
      - no_data_state (optional, default "OK") OK|Alerting|NoData.

    Fully additive: defaults to [], so existing consumers are unaffected.
  EOT
  type = list(object({
    name               = string
    expr               = string
    threshold          = optional(number, 0)
    reducer            = optional(string, "last")
    for_duration       = optional(string, "5m")
    severity           = optional(string, "critical")
    annotations        = optional(map(string), {})
    query_from_seconds = optional(number, 600)
    no_data_state      = optional(string, "OK")
  }))
  default = []

  validation {
    condition     = length(var.metric_rules) == length(distinct([for r in var.metric_rules : r.name]))
    error_message = "metric_rules names must be unique."
  }
  validation {
    condition     = alltrue([for r in var.metric_rules : length(trimspace(r.name)) > 0 && length(trimspace(r.expr)) > 0])
    error_message = "Every metric_rules entry must have a non-empty name and expr."
  }
  validation {
    condition     = alltrue([for r in var.metric_rules : contains(["last", "max", "min", "mean", "sum", "count"], r.reducer)])
    error_message = "metric_rules[*].reducer must be one of: last, max, min, mean, sum, count."
  }
  validation {
    condition     = alltrue([for r in var.metric_rules : contains(["OK", "Alerting", "NoData"], r.no_data_state)])
    error_message = "metric_rules[*].no_data_state must be one of: OK, Alerting, NoData."
  }
  validation {
    condition     = alltrue([for r in var.metric_rules : r.query_from_seconds > 0])
    error_message = "metric_rules[*].query_from_seconds must be a positive number of seconds."
  }
  validation {
    condition     = alltrue([for r in var.metric_rules : can(regex("^([0-9]+(ms|s|m|h|d|w|y))+$", r.for_duration))])
    error_message = "metric_rules[*].for_duration must be a duration like \"30s\", \"5m\", \"1h30m\", or \"0s\"."
  }
}

variable "log_rules" {
  description = <<-EOT
    Additional Loki-backed alert rules, appended to the log rule group AFTER the
    built-in error-log default. Same shape and semantics as metric_rules, except
    `expr` is LogQL. A non-empty list (or the built-in error-log rule) requires
    the Loki datasource to resolve at plan time.

    Typical `expr`: a count-over-window query thresholded by `threshold`, e.g.
    "sum(count_over_time({namespace=\"ns\"} |~ `PATTERN` [10m]))". Ensure
    query_from_seconds covers the window in the selector.

    Fully additive: defaults to [].
  EOT
  type = list(object({
    name               = string
    expr               = string
    threshold          = optional(number, 0)
    reducer            = optional(string, "last")
    for_duration       = optional(string, "5m")
    severity           = optional(string, "warning")
    annotations        = optional(map(string), {})
    query_from_seconds = optional(number, 600)
    no_data_state      = optional(string, "OK")
  }))
  default = []

  validation {
    condition     = length(var.log_rules) == length(distinct([for r in var.log_rules : r.name]))
    error_message = "log_rules names must be unique."
  }
  validation {
    condition     = alltrue([for r in var.log_rules : length(trimspace(r.name)) > 0 && length(trimspace(r.expr)) > 0])
    error_message = "Every log_rules entry must have a non-empty name and expr."
  }
  validation {
    condition     = alltrue([for r in var.log_rules : contains(["last", "max", "min", "mean", "sum", "count"], r.reducer)])
    error_message = "log_rules[*].reducer must be one of: last, max, min, mean, sum, count."
  }
  validation {
    condition     = alltrue([for r in var.log_rules : contains(["OK", "Alerting", "NoData"], r.no_data_state)])
    error_message = "log_rules[*].no_data_state must be one of: OK, Alerting, NoData."
  }
  validation {
    condition     = alltrue([for r in var.log_rules : r.query_from_seconds > 0])
    error_message = "log_rules[*].query_from_seconds must be a positive number of seconds."
  }
  validation {
    condition     = alltrue([for r in var.log_rules : can(regex("^([0-9]+(ms|s|m|h|d|w|y))+$", r.for_duration))])
    error_message = "log_rules[*].for_duration must be a duration like \"30s\", \"5m\", \"1h30m\", or \"0s\"."
  }
}
