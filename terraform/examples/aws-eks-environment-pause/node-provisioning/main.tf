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
# AWS EKS Environment Pause — node-provisioning root
#
# The in-cluster half of ../cluster: Karpenter's prerequisites and controller.
# Its inputs are ../cluster's outputs.
#
# paused = true removes the controller release. The AWS chart installs its
# CRDs from its crds/ directory, which Helm never upgrades or deletes, so
# every NodePool, NodeClaim, and EC2NodeClass stays with no controller acting
# on them; unlike ../../gcp-gke-environment-pause, no separate CRD release is
# needed to keep them. The prerequisites stay, so the controller's role and
# interruption queue are the same on resume.
#
# Order: pause this root before ../cluster and resume it after.
# - Pausing first removes the controller before the baseline group drains, so
#   nothing launches nodes for the pods the drain leaves pending.
# - Resuming last finds the baseline group's nodes back for the controller.
#   With its one replica the Helm install does not wait for the pod, which
#   stays Pending until a baseline node is ready.
#
# Replace placeholder values before applying.
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
  }
}

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "oidc_provider_url" {
  type = string
}

variable "paused" {
  type     = bool
  default  = false
  nullable = false
}

# --- Cluster connection ---

data "aws_eks_cluster" "target" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "target" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.target.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.target.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.target.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.target.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.target.token
}

# --- Karpenter ---

module "karpenter_prereqs" {
  source = "../../../modules/aws-eks-karpenter-prereqs"

  project_name_prefix = var.project_name_prefix
  cluster_name        = var.cluster_name
  oidc_provider_arn   = var.oidc_provider_arn
  oidc_provider_url   = var.oidc_provider_url
}

module "karpenter_controller" {
  count  = var.paused ? 0 : 1
  source = "../../../modules/aws-eks-karpenter-controller"

  cluster_name                      = var.cluster_name
  cluster_endpoint                  = data.aws_eks_cluster.target.endpoint
  karpenter_controller_role_arn     = module.karpenter_prereqs.controller_role_arn
  karpenter_interruption_queue_name = module.karpenter_prereqs.sqs_queue_name
  # The chart keeps each replica off Karpenter's nodes and on its own node,
  # and ../cluster's baseline group runs one node, so one replica fits it.
  controller_replicas = 1
}

# The controller does not drain or delete the nodes it launched when it is
# removed, so a pause is refused while any exist rather than leaving them
# running with nothing to consolidate them. The check runs when the plan is
# made.
data "kubernetes_resources" "nodeclaim_crd" {
  count = var.paused ? 1 : 0

  api_version    = "apiextensions.k8s.io/v1"
  kind           = "CustomResourceDefinition"
  field_selector = "metadata.name=nodeclaims.karpenter.sh"
}

# Without the NodeClaim CRD (an environment created already paused) there
# can be no NodeClaims, and listing the kind would fail.
data "kubernetes_resources" "nodeclaims" {
  count = var.paused && length(coalesce(try(data.kubernetes_resources.nodeclaim_crd[0].objects, null), [])) > 0 ? 1 : 0

  api_version = "karpenter.sh/v1"
  kind        = "NodeClaim"

  lifecycle {
    postcondition {
      condition     = length(coalesce(self.objects, [])) == 0
      error_message = "Karpenter has nodes (NodeClaims exist). Removing its controller would leave them running and billing with nothing to consolidate them, so this root does not pause while any exist."
    }
  }
}

output "karpenter_release_name" {
  description = "Null while paused."
  value       = one(module.karpenter_controller[*].release_name)
}
