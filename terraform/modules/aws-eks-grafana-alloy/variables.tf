variable "enabled" {
  description = "Master switch for the Grafana k8s-monitoring (Alloy) release. The release is ALSO gated on the Prometheus/Loki endpoints + usernames and a credential source (token or secret) being present, so leaving this true keeps the release inert (count=0) until those are supplied. Set false to hard-disable regardless of credentials."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Value for the cluster.name external label on every shipped metric/log. Typically the EKS cluster name."
  type        = string
}

variable "chart_version" {
  description = "Pinned Grafana k8s-monitoring Helm chart version (v4+ destinations schema). See https://github.com/grafana/k8s-monitoring-helm/releases. Never float — bump deliberately."
  type        = string
  default     = "4.0.0"
}

variable "namespace" {
  description = "Namespace for the k8s-monitoring collectors (Alloy + kube-state-metrics)."
  type        = string
  default     = "observability"
}

variable "create_namespace" {
  description = "Whether the Helm release should create the namespace if it does not exist."
  type        = bool
  default     = true
}

# --- Grafana Cloud routing (public endpoints) ---

variable "prometheus_url" {
  description = "Grafana Cloud Prometheus remote-write endpoint (the .../api/prom/push URL)."
  type        = string
  default     = null
}

variable "prometheus_username" {
  description = "Grafana Cloud Prometheus username (numeric instance ID). Used as the basic-auth username for metrics when shipping inline (var.grafana_cloud_token)."
  type        = string
  default     = null
  sensitive   = true
}

variable "loki_url" {
  description = "Grafana Cloud Loki logs push endpoint (the .../loki/api/v1/push URL)."
  type        = string
  default     = null
}

variable "loki_username" {
  description = "Grafana Cloud Loki username (numeric instance ID, DISTINCT from the Prometheus username). Basic-auth username for logs when shipping inline."
  type        = string
  default     = null
  sensitive   = true
}

# --- Credential source: inline token OR pre-existing Kubernetes Secret ---

variable "grafana_cloud_token" {
  description = "Grafana Cloud access-policy token (metrics:write + logs:write) used as the basic-auth password for BOTH destinations. INLINE path: the token is interpolated into the chart values and therefore lands in Terraform state. Prefer credentials_secret_name in production. Mutually exclusive with credentials_secret_name; the secret reference wins if both are set."
  type        = string
  default     = null
  sensitive   = true
}

variable "credentials_secret_name" {
  description = "Name of a pre-existing Kubernetes Secret referenced via the chart's v4 destinations[].secret (create=false). State-safe alternative to grafana_cloud_token — no credential enters Terraform state. When set, this wins over the inline prometheus_username/loki_username/grafana_cloud_token. NOTE: with create=false the chart reads BOTH the username and the password for each destination from this secret via their *_key fields, so the secret must contain three keys: the Prometheus username, the Loki username, and the shared token (see the *_key variables)."
  type        = string
  default     = null
}

variable "credentials_secret_namespace" {
  description = "Namespace of credentials_secret_name. Defaults to var.namespace when null (the usual case: the secret lives alongside the collectors)."
  type        = string
  default     = null
}

variable "credentials_secret_token_key" {
  description = "Key in credentials_secret_name holding the Grafana Cloud token (the basic-auth password for BOTH destinations). Secret-ref path only."
  type        = string
  default     = "token"
}

variable "credentials_secret_prometheus_username_key" {
  description = "Key in credentials_secret_name holding the Prometheus (metrics) basic-auth username. Secret-ref path only."
  type        = string
  default     = "prometheus-username"
}

variable "credentials_secret_loki_username_key" {
  description = "Key in credentials_secret_name holding the Loki (logs) basic-auth username. Secret-ref path only."
  type        = string
  default     = "loki-username"
}

# --- Feature toggles (map 1:1 to k8s-monitoring v4 feature keys) ---

variable "cluster_metrics_enabled" {
  description = "Enable clusterMetrics (kube-state-metrics + kubelet/cAdvisor -> pod CPU/mem/restarts/OOM)."
  type        = bool
  default     = true
}

variable "cluster_events_enabled" {
  description = "Enable clusterEvents (Kubernetes events -> Loki)."
  type        = bool
  default     = true
}

variable "pod_logs_enabled" {
  description = "Enable podLogsViaLoki (pod stdout/stderr -> Loki)."
  type        = bool
  default     = true
}

variable "annotation_autodiscovery_enabled" {
  description = "Enable annotationAutodiscovery: the metrics collector scrapes Pods/Services annotated `k8s.grafana.com/scrape: \"true\"` (with optional `k8s.grafana.com/metrics.*` port/path/scheme/interval/container annotations) and ships those application metrics to the Prometheus destination. Default false: enabling it widens scrape scope and active-series cost, so opt in deliberately. For multi-container Pods, target a specific container/port or add discovery/metric relabeling via extra_helm_values to avoid duplicate series. Advanced sub-configuration (annotation remap, namespace/label filters, per-port targeting, discovery or metric-processing rules) is available via extra_helm_values."
  type        = bool
  default     = false
}

variable "helm_timeout" {
  description = "Helm release timeout in seconds. wait=true, so a green apply means the collectors actually came up."
  type        = number
  default     = 600
}

variable "extra_helm_values" {
  description = "Additional Helm values YAML strings appended AFTER module-managed values. Last value wins (standard Helm merge). Use for collectors/telemetry overrides or any chart value not exposed as a module variable."
  type        = list(string)
  default     = []
}
