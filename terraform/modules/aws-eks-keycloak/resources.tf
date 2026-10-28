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
  source = "../aws-keycloak"

  release_name           = var.release_name
  namespace              = var.namespace
  create_namespace       = var.create_namespace
  keycloak_chart_version = var.keycloak_chart_version
  keycloak_image_tag     = var.keycloak_image_tag
  db_secret_arn          = var.db_secret_arn
  db_endpoint            = var.db_endpoint
  db_port                = var.db_port
  db_name                = var.db_name
  db_user                = var.db_user
  db_password            = var.db_password
  admin_secret_arn       = var.admin_secret_arn
  admin_user             = var.admin_user
  admin_password         = var.admin_password
  realm_json_path        = var.realm_json_path
  service_port           = var.service_port
  service_type           = var.service_type
  replicas               = var.replicas
  pod_annotations        = var.pod_annotations
  labels = merge({
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "keycloak"
    "eks.amazonaws.com/cluster"    = var.cluster_name
  }, var.tags)
  db_secret_annotations     = { "secrets-manager/arn" = var.db_secret_arn }
  admin_secret_annotations  = var.admin_secret_arn != null ? { "secrets-manager/arn" = var.admin_secret_arn } : {}
  resources_requests_cpu    = var.resources_requests_cpu
  resources_requests_memory = var.resources_requests_memory
  resources_limits_cpu      = var.resources_limits_cpu
  resources_limits_memory   = var.resources_limits_memory
  helm_timeout              = var.helm_timeout
  extra_helm_values         = var.extra_helm_values
}
