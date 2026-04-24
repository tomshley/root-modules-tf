terraform {
  # Cross-variable references inside validation blocks in variables.tf
  # (RDS identifier length check referencing project_name_prefix + workload_name,
  # cluster-vs-tenant database_name overlap check, per-tenant IAM policy name
  # length check) require Terraform >= 1.9 / OpenTofu >= 1.8. Older CLIs emit a
  # cryptic "Variables not allowed" parse error rather than an actionable
  # "upgrade your CLI" message.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
