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

# Example: GitHub Actions → GCP → GKE deploy access
#
# GitHub Actions OIDC issuer: https://token.actions.githubusercontent.com
# Attribute mapping: repository, actor, ref
# Condition: restrict to specific repository

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

module "github_deploy" {
  source = "../../modules/gcp-gke-ci-oidc-access"

  project_id            = "my-gcp-project"
  pool_id               = "github-ci-pool"
  pool_display_name     = "GitHub CI Pool"
  provider_id           = "github-oidc"
  provider_display_name = "GitHub Actions OIDC"
  service_account_id    = "github-ci-deploy"

  # GitHub Actions OIDC
  oidc_issuer_url = "https://token.actions.githubusercontent.com"

  # Map GitHub token claims to Google attributes
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only allow tokens from this specific repository
  attribute_condition = "assertion.repository == 'my-org/my-app'"

  # GKE deploy access
  project_roles = [
    "roles/container.developer",
    "roles/artifactregistry.reader"
  ]

}
