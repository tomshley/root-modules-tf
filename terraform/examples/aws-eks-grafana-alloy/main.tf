###############################################################################
# AWS EKS Grafana Alloy (k8s-monitoring) — Standalone Example
#
# Ships cluster/pod metrics and pod logs from an existing EKS cluster to a
# Grafana Cloud backend (any Prometheus-remote-write + Loki-push endpoints
# work). This example shows the INLINE-token credential path so every input is
# visible. For production prefer the state-safe pre-existing-Secret path: drop
# grafana_cloud_token / prometheus_username / loki_username and set
# credentials_secret_name instead (see the credentials_secret_* variables).
#
# Application metrics opt in from their own Pod template or Service annotations:
#   k8s.grafana.com/scrape: "true"
#   k8s.grafana.com/metrics.portNumber: "9090" # or metrics.portName
#   k8s.grafana.com/metrics.path: "/metrics"   # default: /metrics
# Optional annotations include metrics.scheme, metrics.scrapeInterval,
# metrics.scrapeTimeout, metrics.container, job, and instance.
# For multi-container Pods, target a specific container/port to avoid duplicate
# series that differ only by container label.
#
# Requires a `helm` provider configured against the target cluster.
# Replace placeholder values before applying.
###############################################################################

variable "cluster_name" {
  type    = string
  default = "example-eks-cluster"
}

variable "prometheus_url" {
  type    = string
  default = "https://prometheus-prod-00-prod-us-east-0.grafana.net/api/prom/push"
}

variable "loki_url" {
  type    = string
  default = "https://logs-prod-000.grafana.net/loki/api/v1/push"
}

variable "prometheus_username" {
  type    = string
  default = "000000" # Grafana Cloud Prometheus instance ID
}

variable "loki_username" {
  type    = string
  default = "000000" # Grafana Cloud Loki instance ID (distinct from Prometheus)
}

variable "grafana_cloud_token" {
  type      = string
  sensitive = true
  default   = "glc_REPLACE_WITH_YOUR_GRAFANA_CLOUD_TOKEN"
}

module "grafana_alloy" {
  source = "../../modules/aws-eks-grafana-alloy"

  cluster_name = var.cluster_name
  namespace    = "observability"

  prometheus_url = var.prometheus_url
  loki_url       = var.loki_url

  # Inline credential path: the token is interpolated into the chart values and
  # therefore lands in Terraform state. See the header for the state-safe
  # pre-existing-Secret alternative.
  prometheus_username = var.prometheus_username
  loki_username       = var.loki_username
  grafana_cloud_token = var.grafana_cloud_token

  # Scrape application Pods/Services annotated `k8s.grafana.com/scrape: "true"`
  # and ship their metrics to the Prometheus destination. Workloads opt in with
  # their own annotations; enabling this here only turns the collector feature on.
  annotation_autodiscovery_enabled = true
}

output "release_enabled" {
  value = module.grafana_alloy.enabled
}

output "credential_source" {
  value = module.grafana_alloy.credential_source
}
