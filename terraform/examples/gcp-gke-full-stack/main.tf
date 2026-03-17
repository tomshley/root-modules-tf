###############################################################################
# GCP GKE Full Stack — Reference Composition
#
# Demonstrates output-only wiring between modules.
# Zero depends_on. Zero data source lookups for intra-module dependencies.
# Replace placeholder values before applying.
###############################################################################

variable "google_organization_id" {
  type = string
}

variable "google_billing_account" {
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

# --- Project ---

module "project" {
  source = "../../modules/gcp-project-with-api"

  google_organization_id = var.google_organization_id
  google_billing_account = var.google_billing_account
  google_project_id      = var.google_project_id
  project_name_prefix    = var.project_name_prefix
}

# --- Cluster ---

module "cluster" {
  source = "../../modules/gcp-gke-cluster"

  google_organization_id                 = var.google_organization_id
  google_region                          = var.google_region
  google_region_zone                     = var.google_region_zone
  google_project_id                      = module.project.google_project_id
  project_name_prefix                    = var.project_name_prefix
  master_authorized_networks_cidr_blocks = var.master_authorized_networks_cidr_blocks

  # Networking — defaults match existing hardcoded values.
  # Override for multi-cluster or custom networking:
  # subnet_cidr            = "10.0.0.0/16"
  # services_cidr          = "10.4.0.0/14"
  # pods_cidr              = "10.124.0.0/14"
  # master_ipv4_cidr_block = "172.16.0.0/28"
}

# --- System Nodepool ---

module "system_pool" {
  source = "../../modules/gcp-gke-nodepool"

  project_name_prefix                = var.project_name_prefix
  google_region                      = var.google_region
  pool_name_suffix                   = "system"
  google_container_cluster_self_link = module.cluster.google_container_cluster_gke_cluster_self_link
  google_service_account_email       = module.cluster.google_service_account_gke_service_account_email

  machine_type       = "e2-medium"
  initial_node_count = 1
  min_node_count     = 1
  max_node_count     = 3
  spot               = false

  labels = {
    "role" = "system"
  }

  taints = [
    {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  ]
}

# --- Workload Nodepool ---

module "workload_pool" {
  source = "../../modules/gcp-gke-nodepool"

  project_name_prefix                = var.project_name_prefix
  google_region                      = var.google_region
  pool_name_suffix                   = "workload"
  google_container_cluster_self_link = module.cluster.google_container_cluster_gke_cluster_self_link
  google_service_account_email       = module.cluster.google_service_account_gke_service_account_email

  machine_type       = "t2d-standard-2"
  initial_node_count = 1
  min_node_count     = 0
  max_node_count     = 10
  spot               = true

  labels = {
    "role" = "workload"
  }
}

# --- External NAT ---

module "nat" {
  source = "../../modules/gcp-gke-external-nat"

  project_name_prefix              = var.project_name_prefix
  project_id                       = module.project.google_project_id
  google_compute_network_id        = module.cluster.google_compute_network_gke_network_id
  google_compute_subnetwork_id     = module.cluster.google_compute_subnetwork_id
  google_compute_subnetwork_region = module.cluster.google_compute_subnetwork_region
}
