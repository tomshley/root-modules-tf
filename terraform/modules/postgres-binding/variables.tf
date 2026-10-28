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

variable "binding" {
  type = object({
    host                 = string
    port                 = number
    database_name        = string
    tls_required         = bool
    ca_secret_name       = optional(string)
    username_secret_name = string
    password_secret_name = string
    reader_host          = optional(string)
    reader_capable       = bool
  })
  nullable    = false
  description = "Portable PostgreSQL workload binding."

  validation {
    condition     = var.binding.port >= 1 && var.binding.port <= 65535
    error_message = "binding.port must be a valid TCP port."
  }

  validation {
    condition     = !var.binding.tls_required || var.binding.ca_secret_name != null
    error_message = "tls_required bindings must name a CA Secret."
  }

  validation {
    condition     = var.binding.reader_capable == (var.binding.reader_host != null)
    error_message = "reader_capable must match the presence of reader_host."
  }
}
