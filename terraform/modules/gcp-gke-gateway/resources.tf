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

locals {
  attachment_annotations = merge(
    var.load_balancer_ip == null ? {} : { "networking.gke.io/load-balancer-ip-addresses" = var.load_balancer_ip },
    var.internal == true ? { "networking.gke.io/load-balancer-type" = "Internal" } : {}
  )
}

module "gateway" {
  source                    = "../k8s-gateway"
  name                      = var.name
  namespace                 = var.namespace
  create_namespace          = var.create_namespace
  chart_version             = var.chart_version
  listeners                 = var.listeners
  service_type              = var.service_type
  service_annotations       = { for key, value in merge(var.service_annotations, local.attachment_annotations) : key => value if var.internal != false || !contains(["networking.gke.io/load-balancer-type", "cloud.google.com/load-balancer-type"], key) }
  replicas                  = var.replicas
  pdb_min_available         = var.pdb_min_available
  resources_requests_cpu    = var.resources_requests_cpu
  resources_requests_memory = var.resources_requests_memory
  resources_limits_cpu      = var.resources_limits_cpu
  resources_limits_memory   = var.resources_limits_memory
  network_policy_enabled    = var.network_policy_enabled
  labels                    = var.labels
  helm_timeout              = var.helm_timeout
  extra_helm_values         = var.extra_helm_values
}
