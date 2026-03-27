# Example: GitLab CI → GCP → GKE deploy access
#
# GitLab.com OIDC issuer: https://gitlab.com
# Self-managed GitLab: use your GitLab instance URL
# Attribute mapping: project_path, ref, ref_type, namespace_path
# Condition: provider filtering plus exact IAM binding scoped by namespace_path

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

module "gitlab_deploy" {
  source = "../../modules/gcp-gke-ci-oidc-access"

  project_id            = "my-gcp-project"
  pool_id               = "gitlab-ci-pool"
  pool_display_name     = "GitLab CI Pool"
  provider_id           = "gitlab-oidc"
  provider_display_name = "GitLab CI OIDC"
  service_account_id    = "gitlab-ci-deploy"
  repository_selector   = "my-group"
  repository_attribute  = "attribute.namespace_path"

  # GitLab CI OIDC (use your instance URL for self-managed)
  oidc_issuer_url = "https://gitlab.com"

  # Map GitLab token claims to Google attributes
  attribute_mapping = {
    "google.subject"           = "assertion.sub"
    "attribute.project_path"   = "assertion.project_path"
    "attribute.ref"            = "assertion.ref"
    "attribute.ref_type"       = "assertion.ref_type"
    "attribute.namespace_path" = "assertion.namespace_path"
  }

  # Provider-side filtering admits the group path and subgroup paths.
  # Effective impersonation in this example still stays scoped to namespace_path == "my-group"
  # because the IAM binding is an exact match on repository_selector.
  attribute_condition = "assertion.namespace_path == 'my-group' || assertion.namespace_path.startsWith('my-group/')"

  # GKE deploy access
  project_roles = [
    "roles/container.developer",
    "roles/artifactregistry.reader"
  ]

}
