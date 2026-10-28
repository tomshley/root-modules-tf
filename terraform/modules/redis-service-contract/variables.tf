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

variable "contract" {
  type = object({
    mode                 = string
    auth_required        = bool
    tls_required         = bool
    reader_required      = bool
    persistence_required = bool
    availability         = string
  })
  nullable    = false
  description = "Provider-independent Redis service requirements."

  validation {
    condition     = contains(["cache", "retained-state"], var.contract.mode)
    error_message = "contract.mode must be cache or retained-state."
  }

  validation {
    condition     = contains(["single-zone", "multi-zone"], var.contract.availability)
    error_message = "contract.availability must be single-zone or multi-zone."
  }

  validation {
    condition     = var.contract.mode != "retained-state" || var.contract.persistence_required
    error_message = "retained-state requires persistence_required = true."
  }

  validation {
    condition     = !var.contract.reader_required || var.contract.availability == "multi-zone"
    error_message = "reader_required requires a multi-zone service contract."
  }
}
