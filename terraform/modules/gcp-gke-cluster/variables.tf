variable "google_organization_id" {
  type = string
}

variable "google_billing_account" {
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

variable "project_name" {
  type = string
}

# https://github.com/hashicorp/terraform-provider-google/issues/12584#issuecomment-2619971101
variable "kubelet_config" {
  type = object({
    cpu_manager_policy   = optional(string)
    cpu_cfs_quota        = optional(bool)
    cpu_cfs_quota_period = optional(string)
    pod_pids_limit       = optional(number)
  })
  default = {}
}

# variable "google_compute_network_default_id" {
#   type = string
# }
# variable "google_compute_subnetwork_default_id" {
#   type = string
# }
# variable "google_compute_subnetwork_default_secondary_ip_range_range_name_0" {
#   type = string
# }
# variable "google_compute_subnetwork_default_secondary_ip_range_range_name_1" {
#   type = string
# }