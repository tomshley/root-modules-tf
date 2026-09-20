variable "project_id" { type = string }
variable "cluster_name" { type = string }
variable "cluster_location" {
  type        = string
  description = "GKE cluster location used for instance-type discovery. Accepts a region or a zone — the controller derives the compute region from it."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+(-[a-z])?$", var.cluster_location))
    error_message = "cluster_location must be a GCP region (for example us-central1) or zone (for example us-central1-a)."
  }
}

variable "node_location" {
  type        = string
  default     = null
  description = "Exact GKE cluster location used to address the cluster in the provider's GKE node-pool API paths — not a node-placement choice. Normally omit it: the controller defaults it to cluster_location, which is correct both for a regional cluster (whose location is its region) and for a zonal cluster whose cluster_location is its zone. Set it only when cluster_location is a region but the cluster itself is zonal."

  validation {
    condition     = var.node_location == null || can(regex("^[a-z]+-[a-z]+[0-9]+(-[a-z])?$", var.node_location))
    error_message = "node_location must be null or a GCP region (for example us-central1) or zone (for example us-central1-a)."
  }
}
variable "controller_google_service_account_email" { type = string }
variable "node_service_account_email" { type = string }
variable "namespace" {
  type    = string
  default = "karpenter-system"
}
variable "kubernetes_service_account_name" {
  type    = string
  default = "karpenter"
}
variable "node_network_tags" {
  type    = set(string)
  default = []
}
variable "create_namespace" {
  type    = bool
  default = true
}
variable "extra_helm_values" {
  type    = list(string)
  default = []
}
variable "helm_timeout_seconds" {
  type    = number
  default = 300
}
