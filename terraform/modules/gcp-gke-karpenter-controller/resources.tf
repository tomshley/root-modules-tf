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
  effective_node_location = coalesce(var.node_location, var.cluster_location)
  cluster_location_region = regex("^([a-z]+-[a-z]+[0-9]+)(?:-[a-z])?$", var.cluster_location)[0]
}

# The data source reads the cluster at the EFFECTIVE node location on purpose:
# by the provider's contract that value must be exactly where the cluster lives,
# so the read succeeds if and only if the value is right. A zone supplied for a
# regional cluster fails the read at plan time instead of surfacing later as an
# endless controller retry loop on node-pool API paths that never resolve. The
# assertion then cross-checks that cluster_location resolves to the same region
# the cluster actually lives in, so instance-type discovery and pricing are not
# read from the wrong region. It is a check block so this stays advisory — a
# principal lacking container.clusters.get gets a warning, never a broken plan.
check "karpenter_addresses_the_cluster_where_it_lives" {
  data "google_container_cluster" "karpenter_target" {
    project  = var.project_id
    name     = var.cluster_name
    location = local.effective_node_location
  }

  assert {
    condition     = local.cluster_location_region == regex("^([a-z]+-[a-z]+[0-9]+)(?:-[a-z])?$", data.google_container_cluster.karpenter_target.location)[0]
    error_message = "cluster_location resolves to a different region than the cluster found at the effective node location; instance-type discovery and pricing would be read from the wrong region."
  }
}

module "karpenter" {
  source = "../gcp-karpenter-controller"

  project_id                              = var.project_id
  cluster_name                            = var.cluster_name
  cluster_location                        = var.cluster_location
  node_location                           = var.node_location
  namespace                               = var.namespace
  kubernetes_service_account_name         = var.kubernetes_service_account_name
  controller_google_service_account_email = var.controller_google_service_account_email
  node_service_account_email              = var.node_service_account_email
  node_network_tags                       = var.node_network_tags
  create_namespace                        = var.create_namespace
  extra_helm_values                       = var.extra_helm_values
  use_patched_dual_stack_image            = var.use_patched_dual_stack_image
  controller_image                        = var.controller_image
  image_pull_secrets                      = var.image_pull_secrets
  controller_replicas                     = var.controller_replicas
  keep_controller_off_karpenter_nodes     = var.keep_controller_off_karpenter_nodes
  preference_policy                       = var.preference_policy
  controller_priority_class_name          = var.controller_priority_class_name
  helm_timeout_seconds                    = var.helm_timeout_seconds
  bootstrap_node_pool_name                = var.bootstrap_node_pool_name
}
