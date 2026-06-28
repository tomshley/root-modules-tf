# Grafana k8s-monitoring (Alloy) collectors shipping cluster/pod metrics and pod
# logs to two Grafana-Cloud-compatible destinations (Prometheus remote-write +
# Loki). Vendor-neutral: any Prometheus remote-write + Loki push endpoints work,
# not just Grafana Cloud.
#
# The release is null-tolerant: it deploys only when enabled AND both endpoints
# AND a credential source are present, so leaving it enabled on cold-start /
# pre-credential plans keeps it inert (count = 0) instead of erroring.

locals {
  # Presence checks on the sensitive credentials. nonsensitive() is safe here:
  # we only expose WHETHER a credential is set (drives the deploy gate + the
  # credential_source output), never its value. Without this the readiness
  # booleans would taint every output as sensitive.
  has_token         = nonsensitive(var.grafana_cloud_token != null)
  has_prom_username = nonsensitive(var.prometheus_username != null)
  has_loki_username = nonsensitive(var.loki_username != null)

  # Credential source resolution. A pre-existing Kubernetes Secret reference is
  # state-safe (no token in Terraform state) and wins over the inline token.
  use_secret_ref = var.credentials_secret_name != null
  use_inline     = !local.use_secret_ref && local.has_token

  # Both destinations need a push URL.
  endpoints_ready = var.prometheus_url != null && var.loki_url != null

  # Inline path additionally needs the two instance-ID usernames. The secret-ref
  # path carries usernames + token inside the referenced Secret, so the name is
  # the only required input here.
  inline_ready = local.use_inline && local.has_prom_username && local.has_loki_username

  credentials_ready = local.use_secret_ref || local.inline_ready
  release_ready     = var.enabled && local.endpoints_ready && local.credentials_ready

  secret_namespace = coalesce(var.credentials_secret_namespace, var.namespace)

  # Per-destination basic-auth. With a pre-existing secret (create = false) the
  # chart reads BOTH username and password from that secret via their key names;
  # inline mode embeds the literal username + token.
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

  # destinations[].secret block, only emitted for the secret-ref path.
  secret_block = local.use_secret_ref ? {
    secret = {
      create    = false
      name      = var.credentials_secret_name
      namespace = local.secret_namespace
    }
  } : {}

  annotation_autodiscovery_values = var.annotation_autodiscovery_enabled ? {
    annotationAutodiscovery = { enabled = true }
  } : {}

  # v4 requires every enabled feature to be assigned to a named Alloy collector
  # that exists in `collectors`, AND every defined collector to be used by an
  # enabled feature (the chart validates BOTH directions). Chart 4.0.0 ships no
  # named-defaults, so controller types come from explicit presets: metrics on a
  # single-replica deployment, cluster events on a singleton (avoids duplicate
  # events), and pod logs on a per-node daemonset that mounts /var/log. Built
  # from the same toggles so only collectors for enabled features are created.
  collectors = merge(
    var.cluster_metrics_enabled ? { "alloy-metrics" = { presets = ["deployment"] } } : {},
    var.cluster_events_enabled ? { "alloy-singleton" = { presets = ["singleton"] } } : {},
    var.pod_logs_enabled ? { "alloy-logs" = { presets = ["daemonset", "filesystem-log-reader"] } } : {},
  )

  # v4 `destinations` is a name-keyed map. Built with yamlencode so the
  # conditional auth/secret shapes can never produce malformed YAML.
  chart_values = yamlencode(merge({
    cluster = {
      name = var.cluster_name
    }
    destinations = {
      "grafana-cloud-metrics" = merge({
        type = "prometheus"
        url  = var.prometheus_url
        auth = local.metrics_auth
      }, local.secret_block)
      "grafana-cloud-logs" = merge({
        type = "loki"
        url  = var.loki_url
        auth = local.logs_auth
      }, local.secret_block)
    }
    collectors     = local.collectors
    clusterMetrics = { enabled = var.cluster_metrics_enabled, collector = "alloy-metrics" }
    clusterEvents  = { enabled = var.cluster_events_enabled, collector = "alloy-singleton" }
    podLogsViaLoki = { enabled = var.pod_logs_enabled, collector = "alloy-logs" }

    # clusterMetrics needs a kube-state-metrics connection. Deploy the
    # chart-managed KSM (into var.namespace) whenever clusterMetrics is on.
    # Consumers with an existing cluster-wide KSM can override via
    # extra_helm_values (deploy=false + clusterMetrics.kube-state-metrics
    # namespace/labelSelectors).
    telemetryServices = {
      "kube-state-metrics" = { deploy = var.cluster_metrics_enabled }
    }
  }, local.annotation_autodiscovery_values))
}

resource "helm_release" "k8s_monitoring" {
  count = local.release_ready ? 1 : 0

  name             = "grafana-k8s-monitoring"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "k8s-monitoring"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace

  # wait = true so a green apply means the collectors actually came up, not just
  # that the release object was created.
  wait    = true
  timeout = var.helm_timeout

  # Module-managed values first, caller overrides last (standard Helm merge).
  values = concat([local.chart_values], var.extra_helm_values)
}
