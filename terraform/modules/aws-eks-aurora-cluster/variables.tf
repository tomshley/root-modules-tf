variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for all resources created by this module"
}

variable "workload_name" {
  type        = string
  description = "Logical workload name used in all resource naming (e.g. event-journal, readmodel)"

  validation {
    condition     = can(regex("^[a-z](-?[a-z0-9])+$", var.workload_name))
    error_message = "workload_name must be lowercase alphanumeric with single hyphens, starting with a letter, minimum 2 characters."
  }

  # NOTE: the cluster_identifier is "${project_name_prefix}-${workload_name}-db"
  # and the reader instance identifier is
  # "${project_name_prefix}-${workload_name}-db-reader-${N}" where N can reach
  # 15 (reader_instance_count max). "-db-reader-15" is 13 bytes and is the
  # longest generated suffix, so if that fits in 63 bytes (AWS RDS identifier
  # limit) every shorter-suffixed identifier (cluster, writer, subnet group,
  # security group, parameter group) also fits.
  validation {
    condition     = length("${var.project_name_prefix}-${var.workload_name}-db-reader-15") <= 63
    error_message = "Generated RDS identifiers (project_name_prefix + workload_name + suffix) must not exceed 63 bytes (AWS RDS identifier limit). The longest generated suffix this module produces is '-db-reader-15' (13 bytes); if that fits, every shorter-suffixed identifier fits too."
  }
}

variable "workload_preset" {
  type        = string
  default     = "generic"
  description = "Tuning preset. Allowed values: event-store, read-store, generic."

  validation {
    condition     = contains(["event-store", "read-store", "generic"], var.workload_preset)
    error_message = "workload_preset must be one of: event-store, read-store, generic."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group placement"
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for Aurora DB subnet group placement"
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to access the Aurora cluster on the configured port"
}

variable "engine_version" {
  type        = string
  default     = "16.4"
  description = "Aurora PostgreSQL engine version (major version must be 13-17)"
}

variable "database_name" {
  type        = string
  description = "Name of the default database created in the cluster"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]*$", var.database_name))
    error_message = "database_name must be a valid unquoted Postgres identifier (lowercase letters/digits/underscores, starting with a letter or underscore)."
  }

  validation {
    condition     = length(var.database_name) <= 63
    error_message = "database_name must be <= 63 bytes (Postgres NAMEDATALEN limit). Longer names are silently truncated at CREATE DATABASE time, which can silently collide with other identifiers."
  }
}

variable "master_username" {
  type        = string
  default     = "postgres"
  description = "Master username for the Aurora cluster. Must be a valid unquoted Postgres identifier."

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]*$", var.master_username))
    error_message = "master_username must be a valid unquoted Postgres identifier (lowercase letters/digits/underscores, starting with a letter or underscore)."
  }

  validation {
    condition     = length(var.master_username) <= 63
    error_message = "master_username must be <= 63 bytes (Postgres NAMEDATALEN limit)."
  }
}

variable "min_capacity" {
  type        = number
  default     = 0.5
  description = "Minimum ACU capacity for Serverless v2 scaling"
}

variable "max_capacity" {
  type        = number
  default     = 2
  description = "Maximum ACU capacity for Serverless v2 scaling"
}

variable "port" {
  type        = number
  default     = 5432
  description = <<-EOT
    PostgreSQL port for the Aurora cluster.

    Port changes are applied in-place via ModifyDBCluster (the cluster ARN
    does not change), but the module deliberately does NOT auto-sync the new
    port into the master Secrets Manager secret. Any automation that rewrote
    the secret on a port change would re-introduce the "stale Terraform-state
    password overwrites live Postgres password" failure mode that
    `ignore_changes = [secret_string]` on `aws_secretsmanager_secret_version.this`
    was added to prevent (after a Scenario A out-of-band rotation — see the
    runbook in resources.tf). Operators who change this value must re-sync
    the master secret manually via a read-modify-write against the 5-field
    JSON (`username`, `password`, `host`, `port`, `dbname`) — do NOT send a
    partial payload to `aws secretsmanager put-secret-value`, which REPLACES
    the entire secret value and will silently truncate the other four
    fields, breaking every tenant migrate Job and ESO sync. The canonical
    jq-based snippet lives in the `var.port` paragraph of the inline runbook
    next to `aws_secretsmanager_secret_version.this` in resources.tf.
  EOT

  validation {
    condition     = var.port > 0 && var.port < 65536
    error_message = "port must be a valid TCP port (1-65535)."
  }
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Enable deletion protection on the Aurora cluster"
}

variable "skip_final_snapshot" {
  type        = bool
  default     = false
  description = "Skip final snapshot when destroying the cluster"
}

variable "backup_retention_period" {
  type        = number
  default     = 7
  description = "Number of days to retain automated backups"
}

variable "reader_instance_count" {
  type        = number
  default     = 0
  description = "Number of Aurora reader instances to create (0 = writer only)"

  validation {
    condition     = var.reader_instance_count >= 0 && var.reader_instance_count <= 15
    error_message = "reader_instance_count must be between 0 and 15."
  }
}

# --- Tunable parameter overrides (nullable, preset value used when null) ---

variable "max_connections" {
  type        = string
  default     = null
  description = "Optional override for max_connections parameter."
}

variable "wal_buffers" {
  type        = string
  default     = null
  description = "Optional override for wal_buffers parameter (8 kB units)."
}

variable "random_page_cost" {
  type        = string
  default     = null
  description = "Optional override for random_page_cost parameter."
}

variable "work_mem" {
  type        = string
  default     = null
  description = "Optional override for work_mem parameter (kB)."
}

variable "security_group_description" {
  type        = string
  default     = null
  description = "Override for the security group description (ForceNew). Defaults to auto-generated from workload_name. Migrating consumers should pass the old literal to avoid recreation."
}

variable "parameter_group_description" {
  type        = string
  default     = null
  description = "Override for the cluster parameter group description (ForceNew). Defaults to auto-generated from workload_name and preset. Migrating consumers should pass the old literal to avoid recreation."
}

# --- Multi-tenant configuration (optional) ---

variable "master_secret_recovery_window_in_days" {
  type        = number
  default     = 30
  description = "Number of days AWS retains the cluster master secret after a Terraform-driven deletion. Set to 0 to force immediate deletion (non-recoverable) — useful for staging environments that are frequently torn down and rebuilt, since the 30-day AWS default blocks recreation under the same name for the recovery window. Applies to the master (superuser) secret only; per-tenant app secrets are controlled by var.tenant_secret_recovery_window_in_days. NOTE: AWS Secrets Manager exposes this value only to DeleteSecret — changing it on an already-created secret produces a Terraform plan diff but does NOT mutate AWS-side state. The new value takes effect only the next time Terraform destroys this secret."

  validation {
    condition     = var.master_secret_recovery_window_in_days == 0 || (var.master_secret_recovery_window_in_days >= 7 && var.master_secret_recovery_window_in_days <= 30)
    error_message = "master_secret_recovery_window_in_days must be 0 (force delete) or between 7 and 30 days."
  }
}

variable "tenant_secret_recovery_window_in_days" {
  type        = number
  default     = 30
  description = "Number of days AWS retains a deleted tenant secret before permanent deletion. Removing a tenant from var.tenants and re-adding it within this window will fail with InvalidRequestException. Set to 0 to force immediate deletion (non-recoverable). Applies only to per-tenant app secrets, not the master secret. NOTE: same update semantics as master_secret_recovery_window_in_days — changing this on an already-created secret does not mutate AWS-side state; it only affects the next DeleteSecret call."

  validation {
    condition     = var.tenant_secret_recovery_window_in_days == 0 || (var.tenant_secret_recovery_window_in_days >= 7 && var.tenant_secret_recovery_window_in_days <= 30)
    error_message = "tenant_secret_recovery_window_in_days must be 0 (force delete) or between 7 and 30 days."
  }
}

variable "tenants" {
  type = map(object({
    database_name = string
    db_role_name  = optional(string)
  }))
  default     = {}
  description = <<-EOT
    Optional per-tenant configuration for multi-tenant clusters. Each map key
    is a stable tenant name (used in resource names) and each value defines
    the logical database name and optional Postgres role name (defaults to
    the map key with hyphens replaced by underscores when omitted).

    For each tenant, the module creates:
      - One empty Secrets Manager secret named
        "$${project_name_prefix}-$${workload_name}-$${tenant}-app-db".
        The secret is intentionally NOT populated by Terraform; the tenant's
        k8s migrate Job writes the per-tenant credentials after bootstrapping
        the Postgres role + logical database. The migrate Job MUST populate
        the secret with the same JSON schema as the master secret:
        {username, password, host, port, dbname}.
      - One IAM policy ("...-$${tenant}-app-read") granting
        secretsmanager:GetSecretValue + secretsmanager:DescribeSecret on the
        tenant's app secret only. DescribeSecret is required by External
        Secrets Operator and the Secrets Manager CSI driver; without it
        those integrations silently fail. Attach this to the tenant's
        runtime IRSA role.
      - One IAM policy ("...-$${tenant}-migrate") granting:
          * secretsmanager:GetSecretValue + secretsmanager:DescribeSecret
            on the cluster master secret (so the migrate Job can bootstrap
            the per-tenant role + DB). DescribeSecret is granted so migrate
            Jobs that pull the master secret via External Secrets Operator
            or the Secrets Manager CSI driver (both issue DescribeSecret
            unconditionally) work without additional wiring; boto3-based
            migrate Jobs can also use the ARN directly.
          * secretsmanager:DescribeSecret + GetSecretValue +
            PutSecretValue + UpdateSecretVersionStage on the tenant's
            app secret (so the migrate Job can populate it after bootstrap
            and short-circuit regeneration on idempotent re-runs).
        Attach this to the tenant's migrate-Job IRSA role — NOT to the
        runtime role.

    The cluster master secret remains a single cluster-scoped resource.
    Granting the master secret to a tenant's runtime role gives that
    tenant cluster-superuser access across every co-tenant's logical DB
    and violates least-privilege / minimum-necessary access. Use the
    migrate + app policy pair produced by this variable instead.

    IMPORTANT — Tenant removal destroy ordering:
    If you wire IRSA attachments via for_each over this module's
    tenant_app_read_policy_arns / tenant_migrate_policy_arns outputs
    (recommended pattern, see examples/aws-eks-aurora-multi-tenant), Terraform
    will automatically sequence attachment destroy → policy destroy in a single
    apply when you remove a tenant from this map.

    If you instead use hand-rolled aws_iam_role_policy_attachment resources
    that reference policy ARNs as string literals or data lookups (not via
    module outputs), you must remove those attachments first, apply, THEN
    remove the tenant from this map to avoid AWS DeleteConflict errors.

    IMPORTANT — Secret recovery window:
    Deleted tenant secrets enter a recovery window (default 30 days, see
    var.tenant_secret_recovery_window_in_days). Re-adding a tenant with the
    same key within this window will fail with InvalidRequestException. For
    staging environments with frequent tenant churn, consider shortening the
    recovery window.

    Default: {} — no tenants materialized. The module produces only the
    master secret (single-tenant shape), preserving backward compatibility
    with v1.5.x consumers.

    NAMING CONVENTION: Tenant keys use hyphens (kebab-case, IAM-friendly),
    while Postgres role names use underscores. When db_role_name is omitted
    the module derives the role name by substituting underscores for
    hyphens (e.g. key "device-profile" → role "device_profile"). Keys must
    match the IAM-friendly regex and cannot contain underscores. If you
    want a specific role name that differs from this derivation, set
    db_role_name explicitly.
  EOT

  validation {
    condition = alltrue([
      for k, _ in var.tenants : can(regex("^[a-z](-?[a-z0-9])+$", k))
    ])
    error_message = "Tenant keys must be lowercase alphanumeric with single hyphens, starting with a letter, minimum 2 characters. Keys cannot contain underscores; the module derives the Postgres role name by replacing hyphens with underscores."
  }

  validation {
    condition = alltrue([
      for k, v in var.tenants : can(regex("^[a-z_][a-z0-9_]*$", v.database_name))
    ])
    error_message = "tenants[*].database_name must be a valid unquoted Postgres identifier (lowercase letters/digits/underscores, starting with a letter or underscore)."
  }

  validation {
    condition = alltrue([
      for k, v in var.tenants : length(v.database_name) <= 63
    ])
    error_message = "tenants[*].database_name must be <= 63 bytes (Postgres NAMEDATALEN limit). Longer names are silently truncated at CREATE DATABASE time, which can silently collide with other identifiers and defeat the uniqueness validation."
  }

  validation {
    condition = alltrue([
      for k, v in var.tenants :
      v.db_role_name == null || can(regex("^[a-z_][a-z0-9_]*$", v.db_role_name))
    ])
    error_message = "tenants[*].db_role_name must be a valid unquoted Postgres identifier (lowercase letters/digits/underscores, starting with a letter or underscore)."
  }

  # NOTE: the default-derivation expression below must stay in sync with
  # local.resolved_tenant_role_names in locals.tf. Empty-string db_role_name
  # is rejected by the regex validation above, so `!= null` is sufficient here.
  validation {
    condition = alltrue([
      for k, v in var.tenants :
      length(v.db_role_name != null ? v.db_role_name : replace(k, "-", "_")) <= 63
    ])
    error_message = "tenants[*].db_role_name (after applying defaults) must be <= 63 bytes (Postgres NAMEDATALEN limit)."
  }

  validation {
    condition     = length([for k, v in var.tenants : v.database_name]) == length(distinct([for k, v in var.tenants : v.database_name]))
    error_message = "Each tenant must have a unique database_name. Multiple tenants cannot share the same logical database name."
  }

  # NOTE: the default-derivation expression below must stay in sync with
  # local.resolved_tenant_role_names in locals.tf. Terraform validation blocks
  # cannot reference locals, so the expression is duplicated here intentionally.
  # Empty-string db_role_name is rejected by the regex validation above.
  validation {
    condition = (
      length([for k, v in var.tenants : v.db_role_name != null ? v.db_role_name : replace(k, "-", "_")]) ==
      length(distinct([for k, v in var.tenants : v.db_role_name != null ? v.db_role_name : replace(k, "-", "_")]))
    )
    error_message = "Each tenant must have a unique db_role_name (after applying defaults). Multiple tenants cannot share the same Postgres role name."
  }

  validation {
    condition     = !contains([for k, v in var.tenants : v.database_name], var.database_name)
    error_message = "The cluster-level database_name must not equal any tenant's database_name. Tenant migrate Jobs execute CREATE DATABASE unconditionally and will fail if the database already exists. Use a dedicated placeholder such as '<workload_name>_bootstrap'."
  }

  # NOTE: the default-derivation expression below must stay in sync with
  # local.resolved_tenant_role_names in locals.tf. Closes the last naming-
  # collision gap: without this, a tenant key like "postgres" (valid against
  # the tenant-key regex) with no db_role_name override resolves to Postgres
  # role "postgres" and collides with the default var.master_username. The
  # migrate Job would then fail at run time with ERROR: role "postgres"
  # already exists — far from the plan signal. Empty-string db_role_name is
  # rejected by the regex validation above.
  validation {
    condition = alltrue([
      for k, v in var.tenants :
      (v.db_role_name != null ? v.db_role_name : replace(k, "-", "_")) != var.master_username
    ])
    error_message = "tenants[*].db_role_name (after applying defaults) must not equal var.master_username. The migrate Job would attempt CREATE ROLE on an already-existing superuser and fail at run time. Either rename the tenant key, set db_role_name explicitly, or choose a different master_username."
  }

  # NOTE: the default-derivation expression below must stay in sync with
  # local.resolved_tenant_role_names in locals.tf. Denylist of role names
  # Aurora / Postgres reserves:
  #   - "postgres": the conventional superuser; also blocked by the
  #     master_username collision check above when master_username defaults,
  #     but denylisted here independently because an operator can set a
  #     custom master_username and still have a tenant derive to "postgres".
  #   - "rdsadmin": the Aurora-managed maintenance role (cannot be dropped or
  #     re-created; Aurora owns it).
  #   - "rds_superuser", "rds_replication", "rds_iam", "rds_password": AWS-
  #     reserved group roles used by Aurora RDS features. CREATE ROLE of
  #     these either fails or silently aliases in confusing ways.
  #   - "public": Postgres-reserved role name (the implicit pseudo-role every
  #     other role is a member of). Not a `pg_*` prefix match, so the prefix
  #     check below does NOT catch it. CREATE ROLE public fails with
  #     ERROR: role name "public" is reserved.
  #   - "pg_*": prefix reserved by Postgres itself (pg_signal_backend,
  #     pg_read_all_stats, pg_monitor, pg_read_server_files, pg_write_server_files,
  #     pg_execute_server_program, and future additions). CREATE ROLE with
  #     this prefix fails with ERROR: role name "pg_…" is reserved.
  # All checks are against the RESOLVED role name (after the hyphen→underscore
  # default derivation).
  validation {
    condition = alltrue([
      for k, v in var.tenants :
      !contains(
        ["postgres", "rdsadmin", "rds_superuser", "rds_replication", "rds_iam", "rds_password", "public"],
        (v.db_role_name != null ? v.db_role_name : replace(k, "-", "_"))
      )
    ])
    error_message = "tenants[*].db_role_name (after applying defaults) must not be an Aurora/Postgres-reserved role name (postgres, rdsadmin, rds_superuser, rds_replication, rds_iam, rds_password, public). Migrate-Job CREATE ROLE would fail at run time with 'role name \"<name>\" is reserved'."
  }

  validation {
    condition = alltrue([
      for k, v in var.tenants :
      !startswith((v.db_role_name != null ? v.db_role_name : replace(k, "-", "_")), "pg_")
    ])
    error_message = "tenants[*].db_role_name (after applying defaults) must not start with 'pg_'. The 'pg_' prefix is reserved by Postgres; CREATE ROLE fails with 'role name \"pg_…\" is reserved'."
  }

  # NOTE: '-app-read' (9 bytes) is the longest of the per-tenant IAM policy
  # suffixes this module generates. '-migrate' (8 bytes) is shorter, so if
  # '-app-read' fits within 128 bytes then '-migrate' fits too. If a new
  # policy suffix longer than '-app-read' is added, update this check.
  validation {
    condition = alltrue([
      for k, _ in var.tenants :
      length("${var.project_name_prefix}-${var.workload_name}-${k}-app-read") <= 128
    ])
    error_message = "Generated IAM policy names (project_name_prefix + workload_name + tenant + '-app-read') must not exceed 128 bytes (AWS IAM limit). The '-app-read' suffix is the longest of the per-tenant policy suffixes; if it fits the others fit too."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources"
}
