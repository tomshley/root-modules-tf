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
# GCP GKE Environment Pause — cluster root
#
# One of two root modules. This one holds the network, the cluster, its
# baseline node pool, and the Cloud SQL instance; ../node-provisioning holds
# Karpenter, whose helm and kubernetes providers connect through the cluster
# built here, so it is a separate root with separate state.
#
# paused = true removes the compute and Managed Prometheus and keeps
# everything else: the cluster and its control plane, the node pool resource,
# the network, the service accounts, and the Cloud SQL instance with its data.
# Nothing this root outputs changes, so whatever is rendered from those
# outputs stays valid.
#
# Pause ../node-provisioning before this root and resume it after.
# Replace placeholder values before applying.
###############################################################################

variable "google_organization_id" {
  type = string
}

variable "google_project_id" {
  type = string
}

variable "google_region" {
  type    = string
  default = "us-central1"
}

variable "google_region_zone" {
  type    = string
  default = "us-central1-a"
}

variable "project_name_prefix" {
  type    = string
  default = "example-gke"
}

variable "master_authorized_networks_cidr_blocks" {
  type    = list(string)
  default = ["203.0.113.0/24"]
}

variable "paused" {
  type     = bool
  default  = false
  nullable = false
}

# The GKE monitoring components a running cluster collects: the system
# components it always keeps plus the workload metric packages, which GKE
# collects only while Managed Prometheus is on. APISERVER, SCHEDULER, and
# CONTROLLER_MANAGER are added only for control-plane metrics. The provider
# compares the list in order and GKE keeps its own, so a list in any other
# order plans a reorder on every run.
locals {
  monitoring_components = [
    "SYSTEM_COMPONENTS",
    "STORAGE",
    "HPA",
    "POD",
    "DAEMONSET",
    "DEPLOYMENT",
    "STATEFULSET",
    "CADVISOR",
    "KUBELET",
    "DCGM",
    "JOBSET",
  ]
}

# --- Network ---

module "network" {
  source = "../../../modules/gcp-network"

  project_id          = var.google_project_id
  project_name_prefix = var.project_name_prefix
  region              = var.google_region
}

# --- Cluster ---

module "cluster" {
  source = "../../../modules/gcp-gke-cluster"

  google_organization_id                 = var.google_organization_id
  google_region                          = var.google_region
  google_region_zone                     = var.google_region_zone
  google_project_id                      = var.google_project_id
  project_name_prefix                    = var.project_name_prefix
  master_authorized_networks_cidr_blocks = var.master_authorized_networks_cidr_blocks
  google_compute_network_id              = module.network.network_id
  google_compute_subnetwork_id           = module.network.subnetwork_id
  services_secondary_range_name          = module.network.services_secondary_range_name
  pods_secondary_range_name              = module.network.pods_secondary_range_name
  # With no nodes there is nothing to scrape, so a pause turns Managed
  # Prometheus off; GKE accepts only SYSTEM_COMPONENTS while it is off, which
  # the module sets itself. Resuming sets true — null would keep the
  # disabled setting — and passes the metric packages back in the same
  # update, because turning it on alone does not restore them.
  managed_prometheus    = !var.paused
  monitoring_components = var.paused ? null : local.monitoring_components
}

# --- Baseline Nodepool ---

# Paused, the pool is held at zero nodes with the autoscaler off; the pool
# itself stays, so Karpenter can bootstrap from it again on resume. Running,
# node_count is unset and the autoscaler sizes the pool between its bounds.
module "baseline_pool" {
  source = "../../../modules/gcp-gke-nodepool"

  project_name_prefix                = var.project_name_prefix
  google_region                      = var.google_region
  pool_name_suffix                   = "baseline"
  google_container_cluster_location  = module.cluster.google_container_cluster_gke_cluster_location
  google_container_cluster_self_link = module.cluster.google_container_cluster_gke_cluster_self_link
  google_service_account_email       = module.cluster.google_service_account_gke_service_account_email

  machine_type       = "e2-standard-2"
  initial_node_count = 1
  min_node_count     = 1
  max_node_count     = 3
  node_count         = var.paused ? 0 : null
}

# --- Database ---

# Paused, the primary is stopped (NEVER); storage and IP address charges
# continue. Cloud SQL does not support NEVER for a read replica, and the
# module refuses NEVER while readers exist, so this composition has none.
module "database" {
  source = "../../../modules/gcp-cloudsql-postgres"

  project_id                     = var.google_project_id
  project_name_prefix            = var.project_name_prefix
  workload_name                  = "application"
  region                         = var.google_region
  private_network_id             = module.network.network_id
  private_services_connection_id = module.network.private_services_connection_id
  database_name                  = "application"
  # The module's default tier is a db-custom shape, which only ENTERPRISE
  # accepts.
  edition           = "ENTERPRISE"
  activation_policy = var.paused ? "NEVER" : null
}

# --- Outputs for ../node-provisioning ---

output "cluster_name" {
  value = module.cluster.google_container_cluster_gke_cluster_name
}

output "cluster_location" {
  value = module.cluster.google_container_cluster_gke_cluster_location
}

output "baseline_node_pool_name" {
  value = module.baseline_pool.node_pool_name
}

output "node_service_account_email" {
  value = module.cluster.google_service_account_gke_service_account_email
}
