terraform {
  # Cross-variable references inside validation blocks (see variables.tf for
  # the IAM role name length check referencing both project_name_prefix and
  # role_name_suffix) require Terraform >= 1.9 / OpenTofu >= 1.8. Older CLIs
  # emit a cryptic "Variables not allowed" parse error otherwise.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
