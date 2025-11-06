variable "google_region" {
  type = string
}

variable "project_name_prefix" {
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

variable "node_machine_type" {
  type    = string
  default = "t2d-standard-2"
}

variable "node_disk_type" {
  type    = string
  default = "pd-standard"
}
variable "node_disk_size_gb" {
  type    = number
  default = 30
}

variable "node_preemptible" {
  type    = bool
  default = false
}

variable "node_spot" {
  type    = bool
  default = false
}
