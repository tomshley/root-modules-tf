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

module "gcp-project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0.0"

  random_project_id       = false
  name                    = var.google_project_id
  org_id                  = var.google_organization_id
  billing_account         = var.google_billing_account
  default_service_account = "keep"
  labels                  = var.labels

  activate_api_identities = [
  ]

  deletion_policy = "DELETE"
}

module "gcp-project-enable-api" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "~> 18.0.0"
  project_id                  = module.gcp-project.project_id
  depends_on                  = [module.gcp-project]
  disable_services_on_destroy = true
  activate_apis = [
    "iamcredentials.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "redis.googleapis.com",
    "storage.googleapis.com"
  ]
}
