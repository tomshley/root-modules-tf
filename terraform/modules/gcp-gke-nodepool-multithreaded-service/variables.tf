variable "google_region" {
  type = string
}

variable "project_name" {
  type = string
}

variable "google_container_cluster_name" {
  type = string
}

variable "google_service_account_default_account_id" {
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