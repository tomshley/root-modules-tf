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
  # Moves with gcp-karpenter-crds' chart version; the two charts are released
  # together and a controller expects its own CRDs.
  chart_version = "0.6.0"

  upstream_controller_image = {
    repository = "public.ecr.aws/cloudpilotai/gcp/karpenter"
    tag        = "v0.6.0"
  }
  # Vendored build of the same provider carrying the dual-stack NIC patch;
  # tags track the chart version so a chart bump implies the matching patch
  # build rather than a stale controller.
  vendored_dual_stack_image = {
    repository = "registry.gitlab.com/tomshley/brands/global/tware/tech/products/provisioning/vendored/karpenter-provider-gcp/karpenter"
    tag        = "v${local.chart_version}-dualstack"
  }

  contract = module.controller_contract.contract

  controller_image = coalesce(
    var.controller_image,
    var.use_patched_dual_stack_image ? local.vendored_dual_stack_image : null,
    local.upstream_controller_image,
  )
}

module "controller_contract" {
  source = "../karpenter-controller-contract"

  contract = {
    replicas                 = var.controller_replicas
    keep_off_karpenter_nodes = var.keep_controller_off_karpenter_nodes
    preference_policy        = var.preference_policy
    priority_class_name      = var.controller_priority_class_name
  }
}

# The CRDs come from gcp-karpenter-crds, installed first by the caller.
# skip_crds keeps Helm from installing the chart's own crds/ copies on a
# cluster that lacks them, where no release would own them and a later
# gcp-karpenter-crds install would fail on them. Removing this release leaves
# every NodePool, NodeClaim, and GCENodeClass in place with no controller
# acting on them.
#
# Every controller_contract field left null renders nothing, so the chart's
# own setting stands. The chart's disruption budget keeps one pod available,
# which would block every drain of a single replica, so setting the replica
# count also allows one pod to be unavailable. Helm merges the node affinity
# into the chart's default affinity, which keeps its one-replica-per-node pod
# anti-affinity.
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter"
  version          = local.chart_version
  skip_crds        = true

  values = concat([yamlencode(merge(
    {
      credentials = { enabled = false }
      serviceAccount = {
        create = true
        name   = var.kubernetes_service_account_name
        annotations = {
          "iam.gke.io/gcp-service-account" = var.controller_google_service_account_email
        }
      }
      controller = merge(
        {
          image = local.controller_image
          env = concat(
            [{ name = "DEFAULT_NODEPOOL_SERVICE_ACCOUNT", value = var.node_service_account_email }],
            local.contract.preference_policy == null ? [] : [{ name = "PREFERENCE_POLICY", value = local.contract.preference_policy }],
          )
          settings = merge({
            projectID       = var.project_id
            clusterName     = var.cluster_name
            clusterLocation = var.cluster_location
            }, var.node_location == null ? {} : {
            nodeLocation = var.node_location
            }, var.bootstrap_node_pool_name == null ? {} : {
            defaultNodePoolTemplateName = var.bootstrap_node_pool_name
          })
        },
        local.contract.replicas == null ? {} : { replicaCount = local.contract.replicas },
        local.contract.priority_class_name == null ? {} : { priorityClassName = local.contract.priority_class_name },
        local.contract.keep_off_karpenter_nodes != true ? {} : {
          affinity = { nodeAffinity = module.controller_contract.node_affinity_off_karpenter_nodes }
        },
      )
    },
    length(var.image_pull_secrets) > 0 ? { imagePullSecrets = [for s in var.image_pull_secrets : { name = s }] } : {},
    local.contract.replicas == null ? {} : { podDisruptionBudget = { maxUnavailable = 1 } },
  ))], var.extra_helm_values)

  wait    = true
  timeout = var.helm_timeout_seconds
}
