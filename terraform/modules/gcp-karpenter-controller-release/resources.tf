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

  controller_image = coalesce(
    var.controller_image,
    var.use_patched_dual_stack_image ? local.vendored_dual_stack_image : null,
    local.upstream_controller_image,
  )
}

# The CRDs come from gcp-karpenter-crds, installed first by the caller.
# skip_crds keeps Helm from installing the chart's own crds/ copies on a
# cluster that lacks them, where no release would own them and a later
# gcp-karpenter-crds install would fail on them. Removing this release leaves
# every NodePool, NodeClaim, and GCENodeClass in place with no controller
# acting on them.
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.namespace
  create_namespace = var.create_namespace
  repository       = "https://cloudpilot-ai.github.io/karpenter-provider-gcp"
  chart            = "karpenter"
  version          = local.chart_version
  skip_crds        = true

  values = concat([yamlencode(merge({
    credentials = { enabled = false }
    serviceAccount = {
      create = true
      name   = var.kubernetes_service_account_name
      annotations = {
        "iam.gke.io/gcp-service-account" = var.controller_google_service_account_email
      }
    }
    controller = {
      image = local.controller_image
      env   = [{ name = "DEFAULT_NODEPOOL_SERVICE_ACCOUNT", value = var.node_service_account_email }]
      settings = merge({
        projectID       = var.project_id
        clusterName     = var.cluster_name
        clusterLocation = var.cluster_location
        }, var.node_location == null ? {} : {
        nodeLocation = var.node_location
        }, var.bootstrap_node_pool_name == null ? {} : {
        defaultNodePoolTemplateName = var.bootstrap_node_pool_name
      })
    }
  }, length(var.image_pull_secrets) > 0 ? { imagePullSecrets = [for s in var.image_pull_secrets : { name = s }] } : {}))], var.extra_helm_values)

  wait    = true
  timeout = var.helm_timeout_seconds
}
