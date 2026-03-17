variable "google_organization_id" {
  type = string
}

variable "google_region" {
  type = string
}

variable "google_region_zone" {
  type = string
}

variable "google_project_id" {
  type = string
}

variable "project_name_prefix" {
  type = string
}

variable "subnet_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "Primary subnet CIDR for GKE nodes"
}

variable "services_cidr" {
  type        = string
  default     = "10.4.0.0/14"
  description = "Secondary range CIDR for Kubernetes services (alias IP range, may be outside VPC CIDR)"
}

variable "pods_cidr" {
  type        = string
  default     = "10.124.0.0/14"
  description = "Secondary range CIDR for Kubernetes pods (alias IP range, may be outside VPC CIDR)"
}

variable "master_ipv4_cidr_block" {
  type        = string
  default     = "172.16.0.0/28"
  description = "Private IP CIDR for GKE control plane"
}

variable "ipv6_access_type" {
  type        = string
  default     = "INTERNAL"
  description = "IPv6 access type for subnetwork (INTERNAL or EXTERNAL)"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels to apply to GKE resources where supported"
}

variable "master_authorized_networks_cidr_blocks" {
  type = list(string)

  validation {
    condition     = length(var.master_authorized_networks_cidr_blocks) > 0
    error_message = "master_authorized_networks_cidr_blocks must be set."
  }

  description = "CIDR blocks allowed to access the GKE control plane."
}

variable "deletion_protection" {
  type    = bool
  default = true
}
