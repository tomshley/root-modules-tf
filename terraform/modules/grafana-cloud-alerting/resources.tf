# Grafana-managed workload-health alert rules -> a generic webhook contact
# point (incident.io / PagerDuty / Opsgenie / Slack-webhook / ...). House
# defaults catch the three Kubernetes workload signals that are usually worth
# wiring first:
#   1. pod restarts  (crash loop)            - Prometheus / kube-state-metrics
#   2. OOMKilled     (out-of-memory)         - Prometheus / kube-state-metrics
#   3. error logs    (trouble before crash)  - Loki  (optional)
#
# Callers can append arbitrary Prometheus and Loki rules through metric_rules
# and log_rules. The metric and Loki rules live in separate rule groups so the
# Loki dependency can be switched off independently for workloads that do not
# ship logs.
#
# Null-tolerant: with the default require_webhook = true the module deploys only
# when enabled AND webhook_url is set, so leaving it enabled on cold-start keeps
# every resource inert (count = 0). Set require_webhook = false to deploy and
# evaluate the rules before a webhook exists — the contact point is then created
# only once webhook_url is supplied, and until then rules route to the org
# default notification policy. The caller must also fold provider-readiness
# (grafana url + token present) into `enabled`, because the datasource lookups
# below run at plan time.

locals {
  # The webhook contact point is a separate concern from rule existence:
  #   notify = a destination exists (webhook_url set) -> create the contact
  #            point and attach per-rule notification routing to it.
  #   deploy = the rules + folder render; gated on provider-readiness
  #            (var.enabled) unless require_webhook forces a destination first.
  notify = var.enabled && var.webhook_url != null
  deploy = var.enabled && (var.webhook_url != null || !var.require_webhook)

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

  # Neutral annotation defaults; callers override individual keys via the
  # *_annotations vars. tomap() keeps every rule object below at one element
  # type, which the concat()s that build the effective lists require.
  pod_restart_annotations = tomap(merge({
    summary     = "Pod is restarting in ${var.namespace}"
    description = "kube_pod_container_status_restarts_total increased for {{ $labels.pod }} in {{ $labels.namespace }}. Likely a crash loop — check the pod logs."
  }, var.pod_restart_annotations))

  oom_annotations = tomap(merge({
    summary     = "Container OOMKilled in ${var.namespace}"
    description = "A container in {{ $labels.pod }} ({{ $labels.namespace }}) terminated with reason=OOMKilled. Review memory limits and usage."
  }, var.oom_annotations))

  error_log_annotations = tomap(merge({
    summary     = "Error logs detected in ${var.namespace}"
    description = "Matched error log lines in {{ $labels.namespace }}. Leading indicator of trouble that liveness/readiness probes may not catch."
  }, var.error_log_annotations))

  # House-default rules expressed in the SAME object shape as var.metric_rules /
  # var.log_rules so one dynamic "rule" block renders built-ins and caller rules
  # uniformly. `for_duration` (not `for`) avoids the object-key reserved word.
  builtin_metric_rules = concat(
    var.pod_restart_rule_enabled ? [{
      name               = var.pod_restart_rule_name
      expr               = "sum by (pod) (increase(kube_pod_container_status_restarts_total{namespace=\"${var.namespace}\"}[10m]))"
      threshold          = 0
      reducer            = "last"
      for_duration       = var.pod_restart_for
      severity           = var.pod_restart_severity
      annotations        = local.pod_restart_annotations
      query_from_seconds = 600
      no_data_state      = "OK"
    }] : [],
    var.oom_rule_enabled ? [{
      name               = var.oom_rule_name
      expr               = "sum by (pod) (kube_pod_container_status_last_terminated_reason{namespace=\"${var.namespace}\", reason=\"OOMKilled\"})"
      threshold          = 0
      reducer            = "last"
      for_duration       = "0s"
      severity           = var.oom_severity
      annotations        = local.oom_annotations
      query_from_seconds = 600
      no_data_state      = "OK"
    }] : [],
  )

  builtin_log_rules = var.error_log_alert_enabled ? [{
    name               = var.error_log_rule_name
    expr               = "sum(count_over_time({namespace=\"${var.namespace}\"} |~ `${var.error_log_pattern}` [5m]))"
    threshold          = 0
    reducer            = "last"
    for_duration       = var.error_log_for
    severity           = var.error_log_severity
    annotations        = local.error_log_annotations
    query_from_seconds = 600
    no_data_state      = "OK"
  }] : []

  # Built-ins first, then caller rules (appended rules never reorder built-ins).
  metric_rules_effective = concat(local.builtin_metric_rules, var.metric_rules)
  log_rules_effective    = concat(local.builtin_log_rules, var.log_rules)

  # A grafana_rule_group must hold >= 1 rule, so a group deploys only when it has
  # at least one effective rule (and the module as a whole is deploying).
  deploy_metrics = local.deploy && length(local.metric_rules_effective) > 0
  deploy_logs    = local.deploy && length(local.log_rules_effective) > 0
}

# -- Datasource UID lookups ----------------------------------------------------
data "grafana_data_source" "prometheus" {
  count = local.deploy_metrics ? 1 : 0
  name  = local.prometheus_datasource_name
}

data "grafana_data_source" "loki" {
  count = local.deploy_logs ? 1 : 0
  name  = local.loki_datasource_name
}

# -- Folder + webhook contact point -------------------------------------------
resource "grafana_folder" "this" {
  count = local.deploy ? 1 : 0
  title = var.folder_title
}

resource "grafana_contact_point" "webhook" {
  count = local.notify ? 1 : 0
  name  = var.contact_point_name

  webhook {
    url                       = var.webhook_url
    http_method               = var.webhook_http_method
    authorization_scheme      = var.webhook_token != null ? var.webhook_authorization_scheme : null
    authorization_credentials = var.webhook_token
  }
}

# -- Metric rules --------------------------------------------------------------
# Per-rule notification_settings route to the contact point WITHOUT taking over
# the org-wide root notification policy. Requires Grafana 10.4+ (simplified
# routing).
resource "grafana_rule_group" "metrics" {
  count            = local.deploy_metrics ? 1 : 0
  name             = var.rule_group_name
  folder_uid       = grafana_folder.this[0].uid
  interval_seconds = var.evaluation_interval_seconds

  dynamic "rule" {
    for_each = local.metric_rules_effective
    content {
      name           = rule.value.name
      for            = rule.value.for_duration
      condition      = "B"
      no_data_state  = rule.value.no_data_state
      exec_err_state = "Error"

      data {
        ref_id = "A"
        relative_time_range {
          from = rule.value.query_from_seconds
          to   = 0
        }
        datasource_uid = data.grafana_data_source.prometheus[0].uid
        model = jsonencode({
          refId         = "A"
          instant       = true
          range         = false
          expr          = rule.value.expr
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
        model = jsonencode({
          conditions = [{
            evaluator = { params = [rule.value.threshold], type = "gt" }
            operator  = { type = "and" }
            query     = { params = ["A"] }
            reducer   = { params = [], type = rule.value.reducer }
            type      = "query"
          }]
          datasource = { type = "__expr__", uid = "-100" }
          refId      = "B"
          type       = "classic_conditions"
        })
      }

      labels      = merge(var.alert_labels, { severity = rule.value.severity })
      annotations = rule.value.annotations

      dynamic "notification_settings" {
        for_each = local.notify ? [1] : []
        content {
          contact_point = grafana_contact_point.webhook[0].name
          group_by      = var.notification_group_by
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.metric_rules_effective) == length(distinct([for r in local.metric_rules_effective : r.name]))
      error_message = "Effective metric rule names (built-ins + metric_rules) must be unique within the rule group; rename the colliding entry."
    }
  }
}

# -- Log rules -----------------------------------------------------------------
resource "grafana_rule_group" "logs" {
  count            = local.deploy_logs ? 1 : 0
  name             = "${var.rule_group_name}-logs"
  folder_uid       = grafana_folder.this[0].uid
  interval_seconds = var.evaluation_interval_seconds

  dynamic "rule" {
    for_each = local.log_rules_effective
    content {
      name           = rule.value.name
      for            = rule.value.for_duration
      condition      = "B"
      no_data_state  = rule.value.no_data_state
      exec_err_state = "Error"

      data {
        ref_id = "A"
        relative_time_range {
          from = rule.value.query_from_seconds
          to   = 0
        }
        datasource_uid = data.grafana_data_source.loki[0].uid
        model = jsonencode({
          refId         = "A"
          queryType     = "instant"
          expr          = rule.value.expr
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
        model = jsonencode({
          conditions = [{
            evaluator = { params = [rule.value.threshold], type = "gt" }
            operator  = { type = "and" }
            query     = { params = ["A"] }
            reducer   = { params = [], type = rule.value.reducer }
            type      = "query"
          }]
          datasource = { type = "__expr__", uid = "-100" }
          refId      = "B"
          type       = "classic_conditions"
        })
      }

      labels      = merge(var.alert_labels, { severity = rule.value.severity })
      annotations = rule.value.annotations

      dynamic "notification_settings" {
        for_each = local.notify ? [1] : []
        content {
          contact_point = grafana_contact_point.webhook[0].name
          group_by      = var.notification_group_by
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.log_rules_effective) == length(distinct([for r in local.log_rules_effective : r.name]))
      error_message = "Effective log rule names (built-in error log + log_rules) must be unique within the rule group; rename the colliding entry."
    }
  }
}
