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

  selected_preset = local.workload_presets[var.workload_preset]

  resolved_sg_description = var.security_group_description != null ? var.security_group_description : "Aurora PostgreSQL access for ${var.workload_name} workloads"
  resolved_pg_description = var.parameter_group_description != null ? var.parameter_group_description : "Aurora PostgreSQL tuning for ${var.workload_name} (${var.workload_preset} preset)"

  resolved_max_connections  = var.max_connections != null ? var.max_connections : local.selected_preset.max_connections
  resolved_wal_buffers      = var.wal_buffers != null ? var.wal_buffers : local.selected_preset.wal_buffers
  resolved_random_page_cost = var.random_page_cost != null ? var.random_page_cost : local.selected_preset.random_page_cost
  resolved_work_mem         = var.work_mem != null ? var.work_mem : local.selected_preset.work_mem

  # Canonical derivation for per-tenant Postgres role names. Referenced by
  # both the uniqueness validation in variables.tf and the tenant_role_names
  # output; keep in sync by always going through this local.
  #
  # Empty-string `db_role_name` is NOT handled here because the variable's
  # regex validation (`^[a-z_][a-z0-9_]*$`) rejects "" at plan time — the
  # only values that reach this derivation are `null` (meaning: use default)
  # or a valid non-empty identifier. Keep the derivation single-source-of-
  # truth; don't re-introduce a `!= ""` guard.
  resolved_tenant_role_names = {
    for k, v in var.tenants : k => (
      v.db_role_name != null ? v.db_role_name : replace(k, "-", "_")
    )
  }
}
