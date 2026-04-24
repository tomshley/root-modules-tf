output "cluster_endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  value = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  value = var.port
}

output "database_name" {
  value = var.database_name
}

output "master_username" {
  description = "Aurora cluster master (superuser) username for downstream consumers that need to read the master secret (e.g. Keycloak DB credential wiring or per-tenant migrate Jobs). Do NOT expose to runtime workloads."
  value       = var.master_username
}

output "security_group_id" {
  value = aws_security_group.this.id
}

output "master_secret_arn" {
  description = "ARN of the cluster master (superuser) Secrets Manager secret. Required for the Scenario A out-of-band rotation runbook and the var.port manual re-sync runbook (both inlined in resources.tf next to aws_secretsmanager_secret_version.this). **CRITICAL**: Do NOT attach read access to any runtime IRSA role — use the per-tenant policies produced from var.tenants (`tenant_app_read_policy_arns` for runtime, `tenant_migrate_policy_arns` for migrate Jobs) instead."
  value       = aws_secretsmanager_secret.this.arn
}

output "cluster_arn" {
  value = aws_rds_cluster.this.arn
}

output "cluster_id" {
  value = aws_rds_cluster.this.cluster_identifier
}

output "parameter_group_name" {
  value = aws_rds_cluster_parameter_group.this.name
}

# ── Multi-tenant outputs ──────────────────────────────────────────────────
# Empty maps when var.tenants is not set.

output "tenant_secret_arns" {
  description = "Map of tenant key to per-tenant app Secrets Manager secret ARN. Populate via each tenant's migrate Job."
  value       = { for k, s in aws_secretsmanager_secret.tenant : k => s.arn }
}

output "tenant_app_read_policy_arns" {
  description = "Map of tenant key to IAM policy ARN that grants read on the tenant's app secret only. Attach to the tenant's runtime IRSA role."
  value       = { for k, p in aws_iam_policy.tenant_app_read : k => p.arn }
}

output "tenant_migrate_policy_arns" {
  description = "Map of tenant key to IAM policy ARN that grants master-secret read + tenant-app-secret read+write. Attach to the tenant's migrate-Job IRSA role. **CRITICAL**: Do NOT attach to runtime roles — this grants cluster superuser access."
  value       = { for k, p in aws_iam_policy.tenant_migrate : k => p.arn }
}

output "tenant_database_names" {
  description = "Map of tenant key to per-tenant logical database name. Hand to the tenant's migrate Job so it can CREATE DATABASE."
  value       = { for k, v in var.tenants : k => v.database_name }
}

output "tenant_role_names" {
  description = "Map of tenant key to per-tenant Postgres role name. Always a valid unquoted Postgres identifier regardless of tenant key (migrate Jobs can CREATE ROLE without quoting). Derived from `db_role_name` when provided, otherwise from the tenant key with hyphens replaced by underscores (e.g. `device-profile` → `device_profile`). Hand to the tenant's migrate Job."
  value       = local.resolved_tenant_role_names
}

output "tenant_secret_recovery_window_in_days" {
  description = "Echo of the recovery window (in days) applied to each per-tenant app secret. Useful for audit/plan review; AWS Secrets Manager enforces this at DeleteSecret time."
  value       = var.tenant_secret_recovery_window_in_days
}

output "master_secret_recovery_window_in_days" {
  description = "Echo of the recovery window (in days) applied to the cluster master secret. Useful for audit/plan review; AWS Secrets Manager enforces this at DeleteSecret time."
  value       = var.master_secret_recovery_window_in_days
}
