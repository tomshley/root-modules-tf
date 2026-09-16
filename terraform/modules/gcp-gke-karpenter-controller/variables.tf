variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name."
}

variable "cluster_location" {
  type        = string
  description = "GKE cluster location for instance type discovery."
}

variable "node_location" {
  type        = string
  description = "Exact GKE cluster location used for GKE API calls."
}

variable "namespace" {
  type        = string
  default     = "karpenter-system"
  description = "Namespace where the Karpenter chart creates its Kubernetes ServiceAccount."
}

variable "kubernetes_service_account_name" {
  type        = string
  default     = "karpenter"
  description = "Kubernetes ServiceAccount name managed by the Karpenter Helm chart."
}

variable "controller_google_service_account_email" {
  type        = string
  description = "Google service-account email created by gcp-karpenter-prereqs."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.iam\\.gserviceaccount\\.com$", var.controller_google_service_account_email))
    error_message = "controller_google_service_account_email must be a valid Google service-account email."
  }
}

variable "node_service_account_email" {
  type        = string
  description = "Google service account attached to Karpenter-provisioned GKE nodes."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.iam\\.gserviceaccount\\.com$", var.node_service_account_email))
    error_message = "node_service_account_email must be a valid Google service-account email."
  }
}

variable "node_network_tags" {
  type        = set(string)
  default     = []
  description = "Explicit network tags to place in each GCENodeClass spec.networkTags."
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether Helm creates the Karpenter namespace."
}

variable "extra_helm_values" {
  type        = list(string)
  default     = []
  description = "Additional Helm values appended after module-managed values."
}
