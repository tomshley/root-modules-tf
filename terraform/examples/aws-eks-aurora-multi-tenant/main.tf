###############################################################################
# AWS EKS Aurora — Multi-Tenant Example
#
# Shared Aurora PostgreSQL cluster hosting multiple per-service logical
# databases. Each tenant gets:
#   - An empty app Secrets Manager secret (populated by the tenant's
#     k8s migrate Job after bootstrap — NOT by Terraform).
#   - A runtime IRSA role with read access to its own app secret only.
#   - A migrate-Job IRSA role with master-secret read + tenant-app-secret
#     write so it can CREATE ROLE / CREATE DATABASE / GRANT and then
#     populate the app secret with the scoped credentials.
#
# The cluster master secret is NEVER attached to a runtime role.
#
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN from the EKS cluster module. Required — no default to prevent accidental apply with fictitious values."
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL (without https://) from the EKS cluster module. Required — no default to prevent accidental apply with fictitious values."
}

variable "tenants" {
  type = map(object({
    database_name           = string
    db_role_name            = optional(string)
    namespace               = string
    app_service_account     = string
    migrate_service_account = string
  }))
  default = {
    service-a = {
      database_name           = "service_a"
      db_role_name            = "service_a_app"
      namespace               = "service-a"
      app_service_account     = "service-a-app"
      migrate_service_account = "service-a-migrate"
    }
    # service-b omits db_role_name to demonstrate the module's default
    # derivation: key "service-b" → Postgres role "service_b" (hyphen
    # replaced with underscore so it's a valid unquoted identifier).
    service-b = {
      database_name           = "service_b"
      namespace               = "service-b"
      app_service_account     = "service-b-app"
      migrate_service_account = "service-b-migrate"
    }
  }
  description = "Per-tenant configuration including both Aurora DB and Kubernetes metadata. Keeping k8s metadata in the same map prevents desync between tenants and IRSA role bindings."
}

# --- Shared cluster with two tenants ---

module "product_db" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "product"
  workload_preset            = "read-store"
  database_name              = "product_bootstrap" # Bootstrap DB only — tenants create their own DBs (see note below)
  reader_instance_count      = 1
  vpc_id                     = "vpc-REPLACE_WITH_YOUR_VPC_ID"
  subnet_ids                 = ["subnet-REPLACE_1", "subnet-REPLACE_2", "subnet-REPLACE_3"]
  allowed_security_group_ids = ["sg-REPLACE_WITH_WORKLOAD_SG"]

  tenants = {
    for k, v in var.tenants : k => {
      database_name = v.database_name
      db_role_name  = v.db_role_name
    }
  }
}

# Note on `database_name`: Aurora requires exactly one database at cluster
# creation, which is what `database_name` drives. In a multi-tenant setup
# the migrate Jobs create per-tenant databases independently; the
# bootstrap database is not used by any tenant — the master user connects
# here to run per-tenant bootstrap. Set it to a stable placeholder name
# you never reference from the app side.

# --- Per-tenant IRSA composition (one pair of roles per tenant) ---
#
# IMPORTANT — for_each source:
# We iterate var.tenants (keys known at plan time) rather than
# module.product_db.tenant_{app_read,migrate}_policy_arns directly. The
# ARNs inside those outputs are unknown until apply, and some Terraform /
# OpenTofu versions reject `for_each` over a value containing unknowns with
# "The 'for_each' map includes keys derived from resource attributes that
# cannot be determined until apply" once downstream expressions chain on.
# Iterating the known input and looking up the unknown ARN by key is the
# canonical safe pattern.
#
# IMPORTANT — Tenant Removal:
# Because these IRSA modules use for_each, Terraform will automatically
# sequence attachment destroy → policy destroy in a single apply when you
# remove a tenant from var.tenants. No two-step process required.
#
# If you instead wire IRSA attachments via hand-rolled
# aws_iam_role_policy_attachment resources (not recommended), you must remove
# those attachments first, apply, THEN remove the tenant to avoid
# DeleteConflict errors.

module "tenant_app_irsa" {
  source   = "../../modules/aws-eks-irsa"
  for_each = var.tenants

  project_name_prefix  = var.project_name_prefix
  role_name_suffix     = "${each.key}-db-app"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = each.value.namespace
  service_account_name = each.value.app_service_account
  policy_arns          = [module.product_db.tenant_app_read_policy_arns[each.key]]
}

module "tenant_migrate_irsa" {
  source   = "../../modules/aws-eks-irsa"
  for_each = var.tenants

  project_name_prefix  = var.project_name_prefix
  role_name_suffix     = "${each.key}-db-migrate"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = each.value.namespace
  service_account_name = each.value.migrate_service_account
  policy_arns          = [module.product_db.tenant_migrate_policy_arns[each.key]]
}

# --- Outputs ---

output "cluster_endpoint" {
  value = module.product_db.cluster_endpoint
}

# Re-exported so the Scenario A rotation runbook (see resources.tf inline
# comment next to aws_secretsmanager_secret_version.this in the module) can
# resolve the ARN via `terraform output -raw master_secret_arn` from this
# stack. Consumer stacks that already aggregate multiple modules may re-
# export under a stack-level alias (e.g. `aurora_master_secret_arn`).
output "master_secret_arn" {
  description = "ARN of the cluster master (superuser) Secrets Manager secret. Required for the Scenario A out-of-band rotation runbook and the var.port manual re-sync runbook — do NOT attach read access to any runtime role."
  value       = module.product_db.master_secret_arn
}

output "tenant_app_secret_arns" {
  description = "Per-tenant app secret ARNs (populated by each tenant's migrate Job)."
  value       = module.product_db.tenant_secret_arns
}

output "tenant_app_role_arns" {
  description = "Per-tenant runtime IRSA role ARNs."
  value       = { for k, m in module.tenant_app_irsa : k => m.role_arn }
}

output "tenant_migrate_role_arns" {
  description = "Per-tenant migrate-Job IRSA role ARNs."
  value       = { for k, m in module.tenant_migrate_irsa : k => m.role_arn }
}

output "tenant_database_names" {
  value = module.product_db.tenant_database_names
}

output "tenant_role_names" {
  value = module.product_db.tenant_role_names
}
