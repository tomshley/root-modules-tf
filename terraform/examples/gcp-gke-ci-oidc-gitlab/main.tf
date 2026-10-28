# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Example: GitLab CI → GCP → GKE deploy access
#
# GitLab.com OIDC issuer: https://gitlab.com
# Self-managed GitLab: use your GitLab instance URL
# Attribute mapping: project_path, ref, ref_type, namespace_path
# Condition: restrict to specific group or project

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

  # Only allow tokens from projects under this group
  attribute_condition = "assertion.namespace_path.startsWith('my-group/')"

  # GKE deploy access
  project_roles = [
    "roles/container.developer",
    "roles/artifactregistry.reader"
  ]

}
