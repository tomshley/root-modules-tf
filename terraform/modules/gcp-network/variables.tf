variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for network resources."
}

variable "region" {
  type        = string
  description = "GCP region for the GKE subnetwork."
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary subnet CIDR for GKE nodes."
}

variable "services_cidr" {
  type        = string
  default     = "10.4.0.0/14"
  description = "Secondary CIDR for Kubernetes Services."
}

variable "pods_cidr" {
  type        = string
  default     = "10.124.0.0/14"
  description = "Secondary CIDR for Kubernetes Pods."
}

variable "ipv6_access_type" {
  type        = string
  default     = "INTERNAL"
  description = "IPv6 access type for the dual-stack subnetwork."

  validation {
    condition     = contains(["INTERNAL", "EXTERNAL"], var.ipv6_access_type)
    error_message = "ipv6_access_type must be INTERNAL or EXTERNAL."
  }
}

variable "private_services_prefix_length" {
  type        = number
  default     = 16
  description = "Prefix length of the VPC range reserved for private Google service producers."

  validation {
    condition     = var.private_services_prefix_length >= 16 && var.private_services_prefix_length <= 24
    error_message = "private_services_prefix_length must be between 16 and 24."
  }
}

variable "node_network_tags" {
  type        = set(string)
  default     = []
  description = "Explicit network tags required by workloads that create nodes outside managed GKE node pools, such as Karpenter NodeClasses."
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels retained in the network contract for downstream consumers."
}
