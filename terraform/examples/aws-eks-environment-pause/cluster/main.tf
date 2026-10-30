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
# tenant secrets. Nothing this root outputs changes, so whatever is rendered
# from those outputs stays valid.
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

# --- Network ---

module "vpc" {
  source = "../../../modules/aws-eks-vpc"

  project_name_prefix  = var.project_name_prefix
  cluster_name         = var.cluster_name
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = ["10.0.0.0/20", "10.0.16.0/20", "10.0.32.0/20"]
  private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20", "10.0.160.0/20"]
}

# --- Cluster ---

module "cluster" {
  source = "../../../modules/aws-eks-cluster"

  project_name_prefix = var.project_name_prefix
  cluster_name        = var.cluster_name
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = concat(module.vpc.private_subnet_ids, module.vpc.public_subnet_ids)
  public_access_cidrs = var.public_access_cidrs
}

# --- Baseline Node Group ---

# Paused, the group is held at zero nodes; the group itself stays. Running,
# node_count is unset and min_size, max_size, and desired_size apply.
module "baseline_nodes" {
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

# --- Database ---

# Paused, the writer and readers are removed and the cluster stays with its
# storage, endpoints, and credentials. Instance charges stop; storage,
# backups, and the module's Secrets Manager secrets keep billing. Resuming
# creates the instances again, each taking several minutes.
module "database" {
  source = "../../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "application"
  database_name              = "application"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.cluster.cluster_security_group_id]
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
