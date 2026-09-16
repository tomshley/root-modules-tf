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

variable "google_compute_network_id" {
  type        = string
  description = "Network ID from gcp-network."
}

variable "google_compute_subnetwork_id" {
  type        = string
  description = "Subnetwork ID from gcp-network."
}

variable "services_secondary_range_name" {
  type        = string
  description = "Services secondary range name from gcp-network."
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Pods secondary range name from gcp-network."
}

variable "master_ipv4_cidr_block" {
  type        = string
  default     = "172.16.0.0/28"
  description = "Private IP CIDR for GKE control plane"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels to apply to GKE resources where supported"
}

variable "enable_private_endpoint" {
  type        = bool
  default     = true
  description = "Whether the GKE control plane uses a private endpoint. Public endpoint access requires explicit authorized CIDRs."
}

variable "master_authorized_networks_cidr_blocks" {
  type    = list(string)
  default = []

  validation {
    condition = alltrue([
      for cidr in var.master_authorized_networks_cidr_blocks : can(cidrhost(cidr, 0))
    ]) && (var.enable_private_endpoint || length(var.master_authorized_networks_cidr_blocks) > 0)
    error_message = "master_authorized_networks_cidr_blocks must contain valid CIDRs and cannot be empty when the public endpoint is enabled."
  }

  description = "CIDR blocks allowed to access the GKE control plane when its public endpoint is enabled."
}

variable "deletion_protection" {
  type    = bool
  default = true
}
