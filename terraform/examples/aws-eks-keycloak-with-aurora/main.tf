###############################################################################
# AWS EKS Keycloak with Aurora — Composed Example
#
# Demonstrates composing aws-eks-aurora-cluster (generic preset) with
# aws-eks-keycloak. The Aurora module provisions the database; the Keycloak
# module deploys the identity server via Helm.
#
# Replace placeholder values before applying.
#
# The Keycloak module resolves DB and admin passwords from Secrets Manager
# at plan time when db_password/admin_password are null — no ESO required
# for first apply. ignore_changes on K8s secret data preserves ESO-managed
# rotation if configured later.
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

  # Multi-instance: release_name prefixes all K8s resources and the Helm
  # release. Use a unique name per instance when deploying multiple Keycloaks
  # in the same namespace.
  release_name = "keycloak"

  db_secret_arn = module.keycloak_db.master_secret_arn
  db_endpoint   = module.keycloak_db.cluster_endpoint
  db_port       = module.keycloak_db.port
  db_name       = module.keycloak_db.database_name
  db_user       = module.keycloak_db.master_username

  admin_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:example-eks-keycloak-admin-AbCdEf"

  # Override the Kubernetes Service port when using a non-standard port or TLS
  # termination. Reflected in base_url, jwks_uri_template, and
  # admin_console_url outputs. Port suffix is omitted when 80.
  # service_port = 8443

  # Escape hatch: append arbitrary Helm values after module-managed values.
  # Last value wins (standard Helm merge semantics). Useful for TLS, ingress,
  # extra env vars, or any chart value not exposed as a module variable.
  # extra_helm_values = [
  #   yamlencode({
  #     ingress = {
  #       enabled   = true
  #       hostname  = "id.example.com"
  #       tls       = true
  #     }
  #   })
  # ]
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
