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

variable "project_id" { type = string }
variable "project_name_prefix" { type = string }
variable "namespace" {
  type    = string
  default = "karpenter-system"
}
variable "kubernetes_service_account_name" {
  type    = string
  default = "karpenter"
}
variable "google_service_account_id" {
  type    = string
  default = "karpenter-controller"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{5,29}$", var.google_service_account_id))
    error_message = "google_service_account_id must be 6-30 lowercase letters, digits, or hyphens, starting with a letter."
  }
}
variable "node_service_account_email" {
  type = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.iam\\.gserviceaccount\\.com$", var.node_service_account_email))
    error_message = "node_service_account_email must be a valid Google service-account email."
  }
}
