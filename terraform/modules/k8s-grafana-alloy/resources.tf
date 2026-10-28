# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

locals {
  has_token         = nonsensitive(var.grafana_cloud_token != null)
  has_prom_username = nonsensitive(var.prometheus_username != null)
  has_loki_username = nonsensitive(var.loki_username != null)
  use_secret_ref    = var.credentials_secret_name != null
  use_inline        = !local.use_secret_ref && local.has_token
  endpoints_ready   = var.prometheus_url != null && var.loki_url != null
  inline_ready      = local.use_inline && local.has_prom_username && local.has_loki_username
  credentials_ready = local.use_secret_ref || local.inline_ready
  release_ready     = var.enabled && local.endpoints_ready && local.credentials_ready
  secret_namespace  = coalesce(var.credentials_secret_namespace, var.namespace)
  metrics_auth = local.use_secret_ref ? {
    type        = "basic"
    usernameKey = var.credentials_secret_prometheus_username_key
    passwordKey = var.credentials_secret_token_key
    } : {
    type     = "basic"
    username = var.prometheus_username
    password = var.grafana_cloud_token
  }
  logs_auth = local.use_secret_ref ? {
    type        = "basic"
    usernameKey = var.credentials_secret_loki_username_key
    passwordKey = var.credentials_secret_token_key
    } : {
    type     = "basic"
    username = var.loki_username
    password = var.grafana_cloud_token
  }
  secret_block = local.use_secret_ref ? {
    secret = {
      create    = false
      name      = var.credentials_secret_name
      namespace = local.secret_namespace
    }
  } : {}
  metrics_collector_enabled = var.cluster_metrics_enabled || var.annotation_autodiscovery_enabled || var.prometheus_operator_objects_enabled
  annotation_autodiscovery_values = var.annotation_autodiscovery_enabled ? {
    annotationAutodiscovery = { enabled = true, collector = "alloy-metrics" }
  } : {}
  prometheus_operator_objects_values = var.prometheus_operator_objects_enabled ? {
    prometheusOperatorObjects = { enabled = true, collector = "alloy-metrics" }
  } : {}
  collectors = merge(
    local.metrics_collector_enabled ? { "alloy-metrics" = { presets = ["deployment"] } } : {},
    var.cluster_events_enabled ? { "alloy-singleton" = { presets = ["singleton"] } } : {},
    var.pod_logs_enabled ? { "alloy-logs" = { presets = ["daemonset", "filesystem-log-reader"] } } : {},
  )
  chart_values = yamlencode(merge({
    cluster = { name = var.cluster_name }
    destinations = {
      "grafana-cloud-metrics" = merge({ type = "prometheus", url = var.prometheus_url, auth = local.metrics_auth }, local.secret_block)
      "grafana-cloud-logs"    = merge({ type = "loki", url = var.loki_url, auth = local.logs_auth }, local.secret_block)
    }
    collectors     = local.collectors
    clusterMetrics = { enabled = var.cluster_metrics_enabled, collector = "alloy-metrics" }
    clusterEvents  = { enabled = var.cluster_events_enabled, collector = "alloy-singleton" }
    podLogsViaLoki = { enabled = var.pod_logs_enabled, collector = "alloy-logs" }
    telemetryServices = {
      "kube-state-metrics" = { deploy = var.cluster_metrics_enabled }
    }
  }, local.annotation_autodiscovery_values, local.prometheus_operator_objects_values))
}

resource "helm_release" "k8s_monitoring" {
  count = local.release_ready ? 1 : 0

  name             = "grafana-k8s-monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "k8s-monitoring"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace
  wait             = true
  timeout          = var.helm_timeout
  values           = concat([local.chart_values], var.extra_helm_values)
}
