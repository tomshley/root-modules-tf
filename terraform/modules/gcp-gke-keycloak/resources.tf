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

module "keycloak" {
  source = "../gcp-keycloak"

  project_id                = var.project_id
  release_name              = var.release_name
  namespace                 = var.namespace
  create_namespace          = var.create_namespace
  chart_version             = var.chart_version
  image_tag                 = var.image_tag
  db_secret_id              = var.db_secret_id
  db_endpoint               = var.db_endpoint
  db_port                   = var.db_port
  db_name                   = var.db_name
  db_user                   = var.db_user
  db_password               = var.db_password
  admin_secret_id           = var.admin_secret_id
  admin_user                = var.admin_user
  admin_password            = var.admin_password
  realm_json_path           = var.realm_json_path
  service_port              = var.service_port
  service_type              = var.service_type
  replicas                  = var.replicas
  pod_annotations           = var.pod_annotations
  labels                    = var.labels
  resources_requests_cpu    = var.resources_requests_cpu
  resources_requests_memory = var.resources_requests_memory
  resources_limits_cpu      = var.resources_limits_cpu
  resources_limits_memory   = var.resources_limits_memory
  helm_timeout              = var.helm_timeout
  extra_helm_values         = var.extra_helm_values
}
