variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Kubernetes namespace for Metrics Server."
}

variable "chart_version" {
  type        = string
  default     = "3.12.1"
  description = "Pinned Metrics Server Helm chart version."
}
