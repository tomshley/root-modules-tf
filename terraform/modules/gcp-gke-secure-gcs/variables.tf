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

variable "bucket_name" {
  type        = string
  description = "Globally unique Cloud Storage bucket name."
}

variable "location" {
  type        = string
  description = "Cloud Storage location."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to delete non-empty bucket contents."
}

variable "versioning_enabled" {
  type        = bool
  default     = false
  description = "Enable object versioning."
}

variable "retention_policy_days" {
  type        = number
  default     = 0
  description = "Retention period in days. Zero disables a bucket retention policy."

  validation {
    condition     = var.retention_policy_days >= 0
    error_message = "retention_policy_days must be zero or greater."
  }
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Labels applied to the bucket."
}
