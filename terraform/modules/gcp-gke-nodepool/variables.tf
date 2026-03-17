variable "project_name_prefix" {
  type = string
}

variable "google_region" {
  type = string
}

variable "pool_name_suffix" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.pool_name_suffix)) && length(var.pool_name_suffix) <= 20
    error_message = "pool_name_suffix must be lowercase alphanumeric + hyphens, max 20 characters."
  }
}

variable "google_container_cluster_self_link" {
  type = string
}

variable "google_service_account_email" {
  type        = string
  default     = "default"
  description = "Service account email for nodes. 'default' uses the default compute engine SA."
}

variable "initial_node_count" {
  type    = number
  default = 1
}

variable "min_node_count" {
  type    = number
  default = 1
}

variable "max_node_count" {
  type    = number
  default = 5
}

variable "location_policy" {
  type    = string
  default = "ANY"
}

variable "machine_type" {
  type    = string
  default = "e2-medium"
}

variable "disk_type" {
  type    = string
  default = "pd-standard"
}

variable "disk_size_gb" {
  type    = number
  default = 30
}

variable "spot" {
  type    = bool
  default = false
}

variable "preemptible" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "taints" {
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []
}

variable "kubelet_config" {
  type = object({
    cpu_manager_policy   = optional(string)
    cpu_cfs_quota        = optional(bool)
    cpu_cfs_quota_period = optional(string)
    pod_pids_limit       = optional(number)
  })
  default = {}
}
