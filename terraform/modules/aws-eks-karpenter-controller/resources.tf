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

###############################################################################
# Karpenter Controller — Helm Release
#
# Installs the Karpenter controller into an existing EKS cluster.
# Requires aws-eks-karpenter-prereqs to be applied first (IAM roles, SQS queue).
#
# Consumers must configure the Helm provider with EKS cluster credentials
# before calling this module.
###############################################################################

module "controller_contract" {
  source = "../karpenter-controller-contract"

  contract = {
    replicas                 = var.controller_replicas
    keep_off_karpenter_nodes = var.keep_controller_off_karpenter_nodes
    preference_policy        = var.preference_policy
    priority_class_name      = var.controller_priority_class_name
  }
}

locals {
  contract = module.controller_contract.contract

  # Karpenter core reads PREFERENCE_POLICY from 1.4.0; the AWS provider and
  # its chart share core's version number. A null or unreadable version
  # counts as older.
  karpenter_version_major    = try(tonumber(split(".", trimprefix(var.karpenter_version, "v"))[0]), null)
  karpenter_version_minor    = try(tonumber(split(".", trimprefix(var.karpenter_version, "v"))[1]), null)
  karpenter_reads_preference = try(local.karpenter_version_major > 1 || local.karpenter_version_major == 1 && local.karpenter_version_minor >= 4, false)
}

# Every controller_contract field left null renders nothing, so the chart's
# own setting stands. From 1.4.0 the chart renders PREFERENCE_POLICY from
# settings.preferencePolicy. The chart's default affinity already keeps the
# controller off Karpenter's nodes; false deletes that node affinity (a null
# value removes the key when Helm merges values), and Helm keeps the chart's
# one-replica-per-node pod anti-affinity either way.
resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = var.karpenter_namespace
  create_namespace = false
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_version

  values = [
    yamlencode(merge(
      {
        settings = merge({
          clusterName       = var.cluster_name
          clusterEndpoint   = var.cluster_endpoint
          interruptionQueue = var.karpenter_interruption_queue_name
        }, local.contract.preference_policy == null ? {} : { preferencePolicy = local.contract.preference_policy })
        serviceAccount = {
          name = var.karpenter_service_account_name
          annotations = {
            "eks.amazonaws.com/role-arn" = var.karpenter_controller_role_arn
          }
        }
      },
      local.contract.replicas == null ? {} : { replicas = local.contract.replicas },
      local.contract.priority_class_name == null ? {} : { priorityClassName = local.contract.priority_class_name },
      local.contract.keep_off_karpenter_nodes == null ? {} : {
        affinity = { nodeAffinity = local.contract.keep_off_karpenter_nodes ? module.controller_contract.node_affinity_off_karpenter_nodes : null }
      },
    ))
  ]

  wait = true

  lifecycle {
    precondition {
      condition     = local.contract.preference_policy == null ? true : local.karpenter_reads_preference
      error_message = "preference_policy needs a karpenter_version that reads as 1.4 or later, because earlier Karpenter does not read PREFERENCE_POLICY; got \"${coalesce(var.karpenter_version, "unset")}\"."
    }
  }
}
