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

variable "tenants" {
  type = map(object({
    database_name = string
    db_role_name  = optional(string)
  }))
  default     = {}
  nullable    = false
  description = "Stable tenant keys and provider-neutral PostgreSQL names."

  validation {
    condition = alltrue([
      for key in keys(var.tenants) : can(regex("^[a-z][a-z0-9-]*$", key))
    ])
    error_message = "Tenant keys must be lowercase DNS-style identifiers."
  }

  validation {
    condition = alltrue([
      for tenant in values(var.tenants) : can(regex("^[a-z_][a-z0-9_]{0,62}$", tenant.database_name))
    ])
    error_message = "Tenant database names must be valid lowercase PostgreSQL identifiers."
  }

  validation {
    condition = alltrue([
      for tenant in values(var.tenants) : tenant.db_role_name == null || can(regex("^[a-z_][a-z0-9_]{0,62}$", tenant.db_role_name))
    ])
    error_message = "Tenant role names must be valid lowercase PostgreSQL identifiers when supplied."
  }

  validation {
    condition = alltrue([
      for key, tenant in var.tenants : length(tenant.db_role_name != null ? tenant.db_role_name : replace(key, "-", "_")) <= 63
    ])
    error_message = "Tenant role names after default derivation must be at most 63 characters."
  }

  validation {
    condition     = length(distinct([for tenant in values(var.tenants) : tenant.database_name])) == length(var.tenants)
    error_message = "Tenant database names must be unique."
  }

  validation {
    condition = length(distinct([
      for key, tenant in var.tenants : tenant.db_role_name != null ? tenant.db_role_name : replace(key, "-", "_")
    ])) == length(var.tenants)
    error_message = "Tenant role names must be unique after default derivation."
  }
}
