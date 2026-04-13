###############################################################################
# AWS EKS Keycloak with Aurora — Composed Example
#
# Demonstrates composing aws-eks-aurora-cluster (generic preset) with
# aws-eks-keycloak. The Aurora module provisions the database; the Keycloak
# module deploys the identity server via Helm.
#
# Replace placeholder values before applying.
#
# This example assumes ExternalSecretsOperator (or CSI Secrets Store Driver)
# syncs DB and admin credentials from Secrets Manager into K8s secrets. For
# non-ESO deployments, also pass db_password and admin_password to the
# keycloak module so Keycloak can connect on first apply.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

# --- Database ---

module "keycloak_db" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "keycloak"
  workload_preset            = "generic"
  database_name              = "keycloak"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]
}

# --- Identity Server ---

module "keycloak" {
  source = "../../modules/aws-eks-keycloak"

  cluster_name = "${var.project_name_prefix}-cluster"
  namespace    = "identity"

  db_secret_arn = module.keycloak_db.master_secret_arn
  db_endpoint   = module.keycloak_db.cluster_endpoint
  db_port       = module.keycloak_db.port
  db_name       = module.keycloak_db.database_name
  db_user       = "postgres"

  admin_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:example-eks-keycloak-admin-AbCdEf"
}

# --- Outputs ---

output "keycloak_db_endpoint" {
  value = module.keycloak_db.cluster_endpoint
}

output "keycloak_db_secret_arn" {
  value = module.keycloak_db.master_secret_arn
}

output "keycloak_base_url" {
  value = module.keycloak.base_url
}

output "keycloak_jwks_uri_template" {
  value = module.keycloak.jwks_uri_template
}

output "keycloak_admin_console" {
  value = module.keycloak.admin_console_url
}

output "keycloak_release_status" {
  value = module.keycloak.release_status
}
