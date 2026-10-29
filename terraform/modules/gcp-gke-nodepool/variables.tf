# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

variable "project_name_prefix" {
  type = string
}

variable "google_region" {
  type = string
}

variable "google_container_cluster_location" {
  type        = string
  default     = null
  description = "Location of the cluster this pool joins; pass the gcp-gke-cluster output google_container_cluster_gke_cluster_location. Null uses google_region, which is correct for regional clusters only. A location that contradicts google_container_cluster_self_link fails at plan time when the self link is known (an existing cluster) and at apply time when it is not yet known (a cluster created in the same run)."
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

variable "node_count" {
  type        = number
  default     = null
  description = "Fixed number of nodes per zone. Null leaves the pool's size to the cluster autoscaler between min_node_count and max_node_count. A number holds the pool at exactly that size with the autoscaler off; 0 removes every node while the pool resource and its cluster remain. min_node_count, max_node_count, and location_policy are ignored while node_count is set, so returning to null restores the same autoscaling bounds."

  validation {
    condition     = var.node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)
    error_message = "node_count must be null or a whole number of nodes, 0 or more."
  }
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
