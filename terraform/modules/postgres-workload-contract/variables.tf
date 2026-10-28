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
    purpose                = string
    reader_required        = bool
    tls_required           = bool
    retention_days         = number
    authoritative          = bool
    projection_rebuildable = bool
  })
  nullable    = false
  description = "Provider-independent PostgreSQL workload requirements. retention_days is the minimum elapsed-day point-in-time recovery window, not a backup-count setting."

  validation {
    condition     = contains(["generic", "event-store", "read-store"], var.contract.purpose)
    error_message = "contract.purpose must be generic, event-store, or read-store."
  }

  validation {
    condition     = var.contract.retention_days >= 1
    error_message = "contract.retention_days must be at least one day."
  }

  validation {
    condition     = var.contract.authoritative != var.contract.projection_rebuildable
    error_message = "An authoritative store is not a rebuildable projection, and a rebuildable projection is not authoritative."
  }

  validation {
    condition = (
      var.contract.purpose == "event-store" && var.contract.authoritative && !var.contract.projection_rebuildable
      ) || (
      var.contract.purpose == "read-store" && !var.contract.authoritative && var.contract.projection_rebuildable
    ) || var.contract.purpose == "generic"
    error_message = "event-store and read-store purposes must carry their matching authority and rebuild semantics."
  }
}
