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

variable "cluster_name" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for node group placement (typically private subnets)"
}

variable "node_group_name" {
  type = string
}

variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "capacity_type" {
  type    = string
  default = "ON_DEMAND"
}

variable "ami_type" {
  type    = string
  default = "AL2023_x86_64_STANDARD"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 5
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "node_count" {
  type        = number
  default     = null
  description = "Fixed number of nodes. Null leaves the group's size to min_size, max_size, and desired_size. A number holds the group at exactly that size: min_size and desired_size take it, and max_size takes it too, or 1 when it is 0, because EKS requires a maximum of at least 1. 0 removes every node while the node group, its launch template, and its role remain. min_size, max_size, and desired_size are ignored while node_count is set, so returning to null restores the same sizes. The counterpart of gcp-gke-nodepool's node_count, which counts nodes per zone where this counts the whole group; both remove every node at 0."

  validation {
    condition     = var.node_count == null || try(var.node_count >= 0 && floor(var.node_count) == var.node_count, false)
    error_message = "node_count must be null or a whole number of nodes, 0 or more."
  }
}

variable "disk_size" {
  type    = number
  default = 30
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

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "Kubernetes version for the node group. If null, inherits cluster version at creation time (no auto-upgrade on subsequent applies)."
}
