variable "metrics_server_version" {
  description = "Metrics Server Helm chart version"
  type        = string
  default     = "3.12.1"
}

variable "metrics_server_namespace" {
  description = "Kubernetes namespace for Metrics Server"
  type        = string
  default     = "kube-system"
}
