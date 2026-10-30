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

# The CRDs and the controller are separate modules so a consumer can keep the
# CRDs — and every NodePool, NodeClaim, and GCENodeClass they hold — while it
# composes the controller or not. This module composes both for existing
# consumers: the moved blocks carry their releases across without a
# reinstall, and the controller release plans one in-place update for
# skip_crds, which changes nothing in the cluster.
module "crds" {
  source = "../gcp-karpenter-crds"

  namespace            = var.namespace
  create_namespace     = var.create_namespace
  helm_timeout_seconds = var.helm_timeout_seconds
}

module "controller" {
  source = "../gcp-karpenter-controller-release"

  project_id                              = var.project_id
  cluster_name                            = var.cluster_name
  cluster_location                        = var.cluster_location
  node_location                           = var.node_location
  bootstrap_node_pool_name                = var.bootstrap_node_pool_name
  controller_google_service_account_email = var.controller_google_service_account_email
  node_service_account_email              = var.node_service_account_email
  namespace                               = var.namespace
  kubernetes_service_account_name         = var.kubernetes_service_account_name
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

  depends_on = [module.crds]
}

moved {
  from = helm_release.crds
  to   = module.crds.helm_release.crds
}

moved {
  from = helm_release.karpenter
  to   = module.controller.helm_release.karpenter
}
