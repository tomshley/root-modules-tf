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
# AWS EKS Environment Pause — cluster root
#
# One of two root modules. This one holds the network, the cluster, its
# baseline node group, and the Aurora cluster; ../node-provisioning holds
# Karpenter, whose helm and kubernetes providers connect through the cluster
# built here, so it is a separate root with separate state. The AWS
# counterpart of ../../gcp-gke-environment-pause.
#
# paused = true removes the compute and keeps everything else: the cluster and
# its control plane, the node group resource, the network, the IAM roles, and
# the Aurora cluster with its storage, endpoints, master credential, and
# tenant secrets.
#
# cluster_enabled = false additionally removes the cluster, the node group,
# and the cluster's OIDC provider while keeping the IAM roles, the KMS key,
# the security groups, the network, and the Aurora cluster — the full "down"
# state. It requires paused = true: an environment without its cluster is
# down, not running. Resuming recreates the cluster and its OIDC provider,
# and ../node-provisioning re-trusts the new issuer automatically.
#
# Nothing this root outputs loses its value while paused; while down, the
# cluster name stays and genuinely cluster-bound outputs return null.
#
# Pause ../node-provisioning before this root and resume it after.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

variable "cluster_name" {
  type    = string
  default = "example-eks-cluster"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_access_cidrs" {
  type    = list(string)
  default = ["203.0.113.0/24"]
}

variable "paused" {
  type     = bool
  default  = false
  nullable = false
}

variable "cluster_enabled" {
  type     = bool
  default  = true
  nullable = false
}

# Removing the cluster while unpaused is not a lifecycle state, so it is
# refused before anything else changes.
resource "terraform_data" "lifecycle_mode" {
  lifecycle {
    precondition {
      condition     = var.paused || var.cluster_enabled
      error_message = "cluster_enabled = false requires paused = true: an environment without its cluster is down, and down stops compute first."
    }
  }
}

# --- Network ---

module "vpc" {
  source = "../../../modules/aws-eks-vpc"

  project_name_prefix  = var.project_name_prefix
  cluster_name         = var.cluster_name
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]

  nat_gateway_enabled = var.cluster_enabled
}

# --- Cluster ---

module "cluster" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = var.project_name_prefix
  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  public_access_cidrs = var.public_access_cidrs
  cluster_enabled     = var.cluster_enabled
}

# --- Baseline Node Group ---

# Paused, the group is held at zero nodes; the group itself stays. Running,
# node_count is unset and min_size, max_size, and desired_size apply.
module "baseline_nodes" {
  count  = var.cluster_enabled ? 1 : 0
  source = "../../../modules/aws-eks-nodegroup"

  project_name_prefix = var.project_name_prefix
  cluster_name        = module.cluster.cluster_name
  subnet_ids          = module.vpc.private_subnet_ids
  node_group_name     = "baseline"

  instance_types = ["t3.large"]
  capacity_type  = "ON_DEMAND"
  min_size       = 1
  max_size       = 3
  desired_size   = 1
  node_count     = var.paused ? 0 : null
}

# The node group gained count with cluster_enabled, moving existing installs
# to the [0] address rather than replacing them.
moved {
  from = module.baseline_nodes
  to   = module.baseline_nodes[0]
}

# --- Database ---

# Paused, the writer and readers are removed and the cluster stays with its
# storage, endpoints, and credentials. Instance charges stop; storage,
# backups, and the module's Secrets Manager secrets keep billing. Resuming
# creates the instances again, each taking several minutes.
module "database" {
  source = "../../../modules/aws-eks-aurora-cluster"

  project_name_prefix = var.project_name_prefix
  workload_name       = "application"
  database_name       = "application"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  # The EKS-managed security group is gone with the cluster; the rule returns
  # with it on resume.
  allowed_security_group_ids = var.cluster_enabled ? [module.cluster.cluster_security_group_id] : []
  activation_policy          = var.paused ? "NEVER" : null
}

# --- Outputs for ../node-provisioning ---

output "cluster_name" {
  value = module.cluster.cluster_name
}

output "oidc_provider_arn" {
  value = module.cluster.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.cluster.oidc_provider_url
}
