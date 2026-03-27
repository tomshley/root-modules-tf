# Example: Bitbucket Pipelines → GCP → GKE deploy access
#
# Bitbucket OIDC issuer: https://api.bitbucket.org/2.0/workspaces/{WORKSPACE}/pipelines-config/identity/oidc
# Attribute mapping: repositoryUuid, workspaceUuid
# Condition: restrict to specific repository UUID

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = "my-gcp-project"
  region  = "us-east1"
}

# Replace these with your actual Bitbucket identifiers
locals {
  bitbucket_workspace = "my-workspace"
  bitbucket_repo_uuid = "{11111111-2222-3333-4444-555555555555}"
}

module "bitbucket_deploy" {
  source = "../../modules/gcp-gke-ci-oidc-access"

  project_id            = "my-gcp-project"
  pool_id               = "bitbucket-ci-pool"
  pool_display_name     = "Bitbucket CI Pool"
  provider_id           = "bitbucket-oidc"
  provider_display_name = "Bitbucket Pipelines OIDC"
  service_account_id    = "bitbucket-ci-deploy"

  # Bitbucket Pipelines OIDC
  oidc_issuer_url        = "https://api.bitbucket.org/2.0/workspaces/${local.bitbucket_workspace}/pipelines-config/identity/oidc"
  oidc_allowed_audiences = ["ari:cloud:bitbucket::workspace/${local.bitbucket_workspace}"]

  # Map Bitbucket token claims to Google attributes
  attribute_mapping = {
    "google.subject"            = "assertion.sub"
    "attribute.repository_uuid" = "assertion.repositoryUuid"
    "attribute.workspace_uuid"  = "assertion.workspaceUuid"
  }

  # Only allow tokens from this specific repository
  attribute_condition = "assertion.repositoryUuid == '${local.bitbucket_repo_uuid}'"

  # GKE deploy access
  project_roles = [
    "roles/container.developer",
    "roles/artifactregistry.reader"
  ]

}
