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
# GCP GKE Environment Pause — node-provisioning root
#
# The in-cluster half of ../cluster: Karpenter's CRDs and controller. Its
# inputs are ../cluster's outputs.
#
# paused = true removes the controller release and keeps the CRD release.
# The CRD release owns every NodePool, NodeClaim, and GCENodeClass — removing
# it would delete them — while removing the controller release leaves them in
# place with no controller acting on them. Whether to compose the controller
# is this root's choice; neither module takes a flag for it.
#
# Order: pause this root before ../cluster and resume it after.
# - Pausing first removes the controller before the baseline pool drains, so
#   nothing launches nodes for the pods the drain leaves pending.
# - Resuming last lets the controller's Helm install, which waits for its pods
#   to be ready, find the baseline pool's nodes back.
#
# Replace placeholder values before applying.
###############################################################################

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
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

variable "project_id" {
  type = string
}

variable "project_name_prefix" {
  type    = string
  default = "example-gke"
}

variable "cluster_name" {
  type = string
}

variable "cluster_location" {
  type = string
}

variable "baseline_node_pool_name" {
  type = string
}

variable "node_service_account_email" {
  type = string
}

# A Secret in karpenter-system that must exist before the controller installs.
# The CRD release creates that namespace in the same apply, so on a new
# cluster create the namespace and Secret first, or have this root own both.
variable "image_pull_secret_name" {
  type    = string
  default = null
}

variable "paused" {
  type     = bool
  default  = false
  nullable = false
}

# --- Cluster connection ---

provider "google" {
  project = var.project_id
}

data "google_client_config" "current" {}

data "google_container_cluster" "target" {
  project  = var.project_id
  name     = var.cluster_name
  location = var.cluster_location
}

provider "helm" {
  kubernetes {
    host                   = "https://${data.google_container_cluster.target.endpoint}"
    cluster_ca_certificate = base64decode(data.google_container_cluster.target.master_auth[0].cluster_ca_certificate)
    token                  = data.google_client_config.current.access_token
  }
}

provider "kubernetes" {
  host                   = "https://${data.google_container_cluster.target.endpoint}"
  cluster_ca_certificate = base64decode(data.google_container_cluster.target.master_auth[0].cluster_ca_certificate)
  token                  = data.google_client_config.current.access_token
}

# --- Karpenter ---

module "karpenter_prereqs" {
  source = "../../../modules/gcp-karpenter-prereqs"

  project_id                 = var.project_id
  project_name_prefix        = var.project_name_prefix
  node_service_account_email = var.node_service_account_email
}

# Installed whether or not paused; it also creates the namespace both
# releases use.
module "karpenter_crds" {
  source = "../../../modules/gcp-karpenter-crds"
}

module "karpenter_controller" {
  count  = var.paused ? 0 : 1
  source = "../../../modules/gcp-karpenter-controller-release"

  project_id                              = var.project_id
  cluster_name                            = var.cluster_name
  cluster_location                        = var.cluster_location
  controller_google_service_account_email = module.karpenter_prereqs.controller_google_service_account_email
  node_service_account_email              = module.karpenter_prereqs.node_service_account_email
  # The controller bootstraps nodes from an existing RUNNING pool's instance
  # template; pin the baseline pool, which stays (at zero nodes) while paused.
  bootstrap_node_pool_name = var.baseline_node_pool_name
  create_namespace         = false
  # See gcp-gke-karpenter-controller-image for why a gcp-gke-cluster cluster
  # needs the patched dual-stack build and when it needs a pull Secret.
  use_patched_dual_stack_image = true
  image_pull_secrets           = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]

  depends_on = [module.karpenter_crds]
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
  count = var.paused && length(try(data.kubernetes_resources.nodeclaim_crd[0].objects, [])) > 0 ? 1 : 0

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
