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
variable "bucket_name" { type = string }
variable "location" { type = string }
variable "force_destroy" {
  type    = bool
  default = false
}
variable "versioning_enabled" {
  type    = bool
  default = false
}
variable "retention_policy_days" {
  type    = number
  default = 0
  validation {
    condition     = var.retention_policy_days >= 0
    error_message = "retention_policy_days must be zero or greater."
  }
}
variable "labels" {
  type    = map(string)
  default = {}
}
