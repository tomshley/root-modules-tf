variable "enabled" {
  type    = bool
  default = true
}
variable "cluster_name" { type = string }
variable "chart_version" {
  type    = string
  default = "4.0.0"
}
variable "namespace" {
  type    = string
  default = "observability"
}
variable "create_namespace" {
  type    = bool
  default = true
}
variable "prometheus_url" {
  type    = string
  default = null
}
variable "prometheus_username" {
  type      = string
  default   = null
  sensitive = true
}
variable "loki_url" {
  type    = string
  default = null
}
variable "loki_username" {
  type      = string
  default   = null
  sensitive = true
}
variable "grafana_cloud_token" {
  type      = string
  default   = null
  sensitive = true
}
variable "credentials_secret_name" {
  type    = string
  default = null
}
variable "credentials_secret_namespace" {
  type    = string
  default = null
}
variable "credentials_secret_token_key" {
  type    = string
  default = "token"
}
variable "credentials_secret_prometheus_username_key" {
  type    = string
  default = "prometheus-username"
}
variable "credentials_secret_loki_username_key" {
  type    = string
  default = "loki-username"
}
variable "cluster_metrics_enabled" {
  type    = bool
  default = true
}
variable "cluster_events_enabled" {
  type    = bool
  default = true
}
variable "pod_logs_enabled" {
  type    = bool
  default = true
}
variable "annotation_autodiscovery_enabled" {
  type    = bool
  default = false
}
variable "prometheus_operator_objects_enabled" {
  type    = bool
  default = false
}
variable "helm_timeout" {
  type    = number
  default = 600
}
variable "extra_helm_values" {
  type    = list(string)
  default = []
}
