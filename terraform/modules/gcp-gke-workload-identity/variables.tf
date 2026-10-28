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

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "service_account_id" {
  type        = string
  description = "Google service-account ID for the workload."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.service_account_id))
    error_message = "service_account_id must be 6-30 lowercase alphanumeric characters or hyphens."
  }
}

variable "namespace" {
  type        = string
  description = "Namespace of the Kubernetes ServiceAccount created by the workload chart or manifest."
}

variable "kubernetes_service_account_name" {
  type        = string
  description = "Name of the Kubernetes ServiceAccount created by the workload chart or manifest."
}

variable "project_roles" {
  type        = list(string)
  default     = []
  description = "Project roles granted to the Google service account."
}

variable "resource_iam_members" {
  type = set(object({
    resource_type = string
    resource_name = string
    role          = string
  }))
  default     = []
  description = "Unbound resource capability descriptors to grant to this workload identity. Supported resource_type: storage_bucket."

  validation {
    condition     = alltrue([for descriptor in var.resource_iam_members : descriptor.resource_type == "storage_bucket"])
    error_message = "resource_iam_members currently supports only storage_bucket capability descriptors."
  }
}

variable "display_name" {
  type        = string
  default     = null
  description = "Optional display name for the Google service account."
}
