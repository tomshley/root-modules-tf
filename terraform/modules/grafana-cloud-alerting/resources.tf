# Grafana-managed workload-health alert rules -> a generic webhook contact
# point (incident.io / PagerDuty / Opsgenie / Slack-webhook / ...). House
# defaults for the three signals that catch a sick Kubernetes workload:
#   1. pod restarts  (crash loop)            — Prometheus / kube-state-metrics
#   2. OOMKilled     (out-of-memory)         — Prometheus / kube-state-metrics
#   3. error logs    (trouble before crash)  — Loki  (optional)
#
# Vendor-neutral: every workload-specific value (namespace, labels, severities,
# the log regex, annotations, datasource names) is an input. The metric rules
# and the Loki rule live in separate rule groups so the log rule — and its Loki
# dependency — can be switched off independently for workloads that do not ship
# logs to Loki.
#
# Null-tolerant: deploys only when enabled AND webhook_url is set, so leaving it
# enabled on cold-start keeps every resource inert (count = 0). The caller must
# also fold provider-readiness (grafana url + token present) into `enabled`,
# because the datasource lookups below run at plan time.

locals {
  deploy      = var.enabled && var.webhook_url != null
  deploy_logs = local.deploy && var.error_log_alert_enabled

  # Grafana Cloud auto-provisions datasources named grafanacloud-<slug>-prom /
  # -logs. Allow explicit override for self-hosted Grafana / non-standard names.
  prometheus_datasource_name = coalesce(
    var.prometheus_datasource_name,
    var.grafana_stack_slug != null ? "grafanacloud-${var.grafana_stack_slug}-prom" : "grafanacloud-prom"
  )
  loki_datasource_name = coalesce(
    var.loki_datasource_name,
    var.grafana_stack_slug != null ? "grafanacloud-${var.grafana_stack_slug}-logs" : "grafanacloud-logs"
  )

  # Shared expression node: fires when query A reduces (last value) to > 0.
  # Built once so the threshold semantics are identical across every rule.
  classic_gt_zero_model = jsonencode({
    conditions = [{
      evaluator = { params = [0], type = "gt" }
      operator  = { type = "and" }
      query     = { params = ["A"] }
      reducer   = { params = [], type = "last" }
      type      = "query"
    }]
    datasource = { type = "__expr__", uid = "-100" }
    refId      = "B"
    type       = "classic_conditions"
  })

  # severity is applied on top of the shared labels and wins on its key.
  pod_restart_labels = merge(var.alert_labels, { severity = var.pod_restart_severity })
  oom_labels         = merge(var.alert_labels, { severity = var.oom_severity })
  error_log_labels   = merge(var.alert_labels, { severity = var.error_log_severity })

  # Neutral defaults; callers override individual keys via the *_annotations vars.
  pod_restart_annotations = merge({
    summary     = "Pod is restarting in ${var.namespace}"
    description = "kube_pod_container_status_restarts_total increased for {{ $labels.pod }} in {{ $labels.namespace }}. Likely a crash loop — check the pod logs."
  }, var.pod_restart_annotations)

  oom_annotations = merge({
    summary     = "Container OOMKilled in ${var.namespace}"
    description = "A container in {{ $labels.pod }} ({{ $labels.namespace }}) terminated with reason=OOMKilled. Review memory limits and usage."
  }, var.oom_annotations)

  error_log_annotations = merge({
    summary     = "Error logs detected in ${var.namespace}"
    description = "Matched error log lines in {{ $labels.namespace }}. Leading indicator of trouble that liveness/readiness probes may not catch."
  }, var.error_log_annotations)
}

# ── Datasource UID lookups ──────────────────────────────────────────
data "grafana_data_source" "prometheus" {
  count = local.deploy ? 1 : 0
  name  = local.prometheus_datasource_name
}

data "grafana_data_source" "loki" {
  count = local.deploy_logs ? 1 : 0
  name  = local.loki_datasource_name
}

# ── Folder + webhook contact point ──────────────────────────────────
resource "grafana_folder" "this" {
  count = local.deploy ? 1 : 0
  title = var.folder_title
}

resource "grafana_contact_point" "webhook" {
  count = local.deploy ? 1 : 0
  name  = var.contact_point_name

  webhook {
    url                       = var.webhook_url
    http_method               = var.webhook_http_method
    authorization_scheme      = var.webhook_token != null ? var.webhook_authorization_scheme : null
    authorization_credentials = var.webhook_token
  }
}

# ── Metric rules (pod restart + OOMKilled) ──────────────────────────
# Per-rule notification_settings route to the contact point WITHOUT taking over
# the org-wide root notification policy. Requires Grafana 10.4+ (simplified
# routing).
resource "grafana_rule_group" "metrics" {
  count            = local.deploy ? 1 : 0
  name             = var.rule_group_name
  folder_uid       = grafana_folder.this[0].uid
  interval_seconds = var.evaluation_interval_seconds

  rule {
    name           = var.pod_restart_rule_name
    for            = var.pod_restart_for
    condition      = "B"
    no_data_state  = "OK"
    exec_err_state = "Error"

    data {
      ref_id = "A"
      relative_time_range {
        from = 600
        to   = 0
      }
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      model = jsonencode({
        refId         = "A"
        instant       = true
        range         = false
        expr          = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"${var.namespace}\"}[10m]))"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }
    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "-100"
      model          = local.classic_gt_zero_model
    }

    labels      = local.pod_restart_labels
    annotations = local.pod_restart_annotations
    notification_settings {
      contact_point = grafana_contact_point.webhook[0].name
      group_by      = var.notification_group_by
    }
  }

  rule {
    name           = var.oom_rule_name
    for            = "0s"
    condition      = "B"
    no_data_state  = "OK"
    exec_err_state = "Error"

    data {
      ref_id = "A"
      relative_time_range {
        from = 600
        to   = 0
      }
      datasource_uid = data.grafana_data_source.prometheus[0].uid
      model = jsonencode({
        refId         = "A"
        instant       = true
        range         = false
        expr          = "sum by (pod) (kube_pod_container_status_last_terminated_reason{namespace=\"${var.namespace}\", reason=\"OOMKilled\"})"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }
    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "-100"
      model          = local.classic_gt_zero_model
    }

    labels      = local.oom_labels
    annotations = local.oom_annotations
    notification_settings {
      contact_point = grafana_contact_point.webhook[0].name
      group_by      = var.notification_group_by
    }
  }
}

# ── Log rule (optional; requires a Loki datasource) ─────────────────
resource "grafana_rule_group" "logs" {
  count            = local.deploy_logs ? 1 : 0
  name             = "${var.rule_group_name}-logs"
  folder_uid       = grafana_folder.this[0].uid
  interval_seconds = var.evaluation_interval_seconds

  rule {
    name           = var.error_log_rule_name
    for            = var.error_log_for
    condition      = "B"
    no_data_state  = "OK"
    exec_err_state = "Error"

    data {
      ref_id = "A"
      relative_time_range {
        from = 600
        to   = 0
      }
      datasource_uid = data.grafana_data_source.loki[0].uid
      model = jsonencode({
        refId         = "A"
        queryType     = "instant"
        expr          = "sum(count_over_time({namespace=\"${var.namespace}\"} |~ `${var.error_log_pattern}` [5m]))"
        intervalMs    = 1000
        maxDataPoints = 43200
      })
    }
    data {
      ref_id = "B"
      relative_time_range {
        from = 0
        to   = 0
      }
      datasource_uid = "-100"
      model          = local.classic_gt_zero_model
    }

    labels      = local.error_log_labels
    annotations = local.error_log_annotations
    notification_settings {
      contact_point = grafana_contact_point.webhook[0].name
      group_by      = var.notification_group_by
    }
  }
}
