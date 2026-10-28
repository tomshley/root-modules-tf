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

locals {
  engine_major_version = split(".", var.engine_version)[0]

  workload_presets = {
    event-store = {
      max_connections  = "400"
      wal_buffers      = "2048"
      random_page_cost = "1.1"
      work_mem         = null
    }
    read-store = {
      max_connections  = null
      wal_buffers      = null
      random_page_cost = "1.1"
      work_mem         = "32768"
    }
    generic = {
      max_connections  = null
      wal_buffers      = null
      random_page_cost = null
      work_mem         = null
    }
  }

  resolved_workload_preset         = var.workload_contract == null ? var.workload_preset : module.workload_contract[0].contract.purpose
  selected_preset                  = local.workload_presets[local.resolved_workload_preset]
  resolved_force_ssl               = var.workload_contract == null ? null : (var.workload_contract.tls_required ? "1" : null)
  resolved_backup_retention_period = var.workload_contract == null ? var.backup_retention_period : max(var.backup_retention_period, module.workload_contract[0].contract.retention_days)

  resolved_sg_description = var.security_group_description != null ? var.security_group_description : "Aurora PostgreSQL access for ${var.workload_name} workloads"
  resolved_pg_description = var.parameter_group_description != null ? var.parameter_group_description : "Aurora PostgreSQL tuning for ${var.workload_name} (${local.resolved_workload_preset} preset)"

  resolved_max_connections  = var.max_connections != null ? var.max_connections : local.selected_preset.max_connections
  resolved_wal_buffers      = var.wal_buffers != null ? var.wal_buffers : local.selected_preset.wal_buffers
  resolved_random_page_cost = var.random_page_cost != null ? var.random_page_cost : local.selected_preset.random_page_cost
  resolved_work_mem         = var.work_mem != null ? var.work_mem : local.selected_preset.work_mem

  resolved_tenant_role_names = {
    for k, binding in module.tenancy_contract.tenant_bindings : k => binding.db_role_name
  }
}
