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
  type        = string
  description = "EKS cluster name. Explicit — not derived internally."

  validation {
    condition     = can(regex("^[0-9A-Za-z][A-Za-z0-9_-]{0,99}$", var.cluster_name))
    error_message = "cluster_name must be at most 100 characters of alphanumerics, hyphens, and underscores, starting with an alphanumeric character — the EKS cluster-name limit."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group placement (from VPC module)"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for EKS cluster networking (from VPC module)"
}

variable "kubernetes_version" {
  type    = string
  default = "1.34"
}

variable "endpoint_public_access" {
  type    = bool
  default = false
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "cluster_log_types" {
  type    = list(string)
  default = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "public_access_cidrs" {
  type = list(string)

  validation {
    condition     = length(var.public_access_cidrs) > 0
    error_message = "public_access_cidrs must be explicitly set."
  }

  description = "Explicit CIDR blocks allowed to access the EKS public API endpoint. Must be provided."
}

variable "authentication_mode" {
  type        = string
  default     = "API_AND_CONFIG_MAP"
  description = "EKS authentication mode. Must be API, API_AND_CONFIG_MAP, or CONFIG_MAP. API or API_AND_CONFIG_MAP is required for EKS access entries."

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: API, API_AND_CONFIG_MAP, CONFIG_MAP"
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  default     = true
  description = "Whether the cluster creator IAM principal gets admin access. ForceNew — must match the value used at cluster creation to avoid replacement."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
