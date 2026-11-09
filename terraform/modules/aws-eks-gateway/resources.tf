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
  caller_load_balancer_attributes = [
    for entry in split(",", try(trimspace(var.service_annotations["service.beta.kubernetes.io/aws-load-balancer-attributes"]), "")) : trimspace(entry)
    if trimspace(entry) != "" && trimspace(split("=", entry)[0]) != "load_balancing.cross_zone.enabled"
  ]
  attachment_tags = merge(var.tags == null ? {} : var.tags, var.nlb_additional_resource_tags == null ? {} : var.nlb_additional_resource_tags)
  attachment_annotations = merge(
    { "service.beta.kubernetes.io/aws-load-balancer-type" = "external" },
    var.nlb_scheme == null ? {} : { "service.beta.kubernetes.io/aws-load-balancer-scheme" = var.nlb_scheme },
    var.nlb_eip_allocations == null ? {} : { "service.beta.kubernetes.io/aws-load-balancer-eip-allocations" = join(",", var.nlb_eip_allocations) },
    var.nlb_cross_zone == null ? {} : { "service.beta.kubernetes.io/aws-load-balancer-attributes" = join(",", concat(local.caller_load_balancer_attributes, ["load_balancing.cross_zone.enabled=${var.nlb_cross_zone}"])) },
    var.nlb_target_type == null ? {} : { "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = var.nlb_target_type },
    length(local.attachment_tags) == 0 ? {} : { "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags" = join(",", [for key, value in local.attachment_tags : "${key}=${value}"]) }
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
  service_annotations       = merge(var.service_annotations, local.attachment_annotations)
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
