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
  gke_service_account_id = lower("${var.project_name_prefix}-${var.google_organization_id}")
  gke_cluster_name       = "${var.project_name_prefix}-standard-cluster"
}

resource "google_service_account" "gke_service_account" {
  account_id = local.gke_service_account_id
  project    = var.google_project_id

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z][a-z0-9-]{5,29}$", local.gke_service_account_id))
      error_message = "The derived GKE service-account ID must be 6-30 characters of lowercase letters, digits, and hyphens, starting with a letter."
    }
  }
}

resource "google_container_cluster" "gke_cluster" {
  depends_on     = [google_service_account.gke_service_account]
  name           = local.gke_cluster_name
  project        = var.google_project_id
  location       = var.location_mode == "zonal" ? var.google_region_zone : var.google_region
  node_locations = var.location_mode == "zonal" ? null : [var.google_region_zone]

  network                  = var.google_compute_network_id
  subnetwork               = var.google_compute_subnetwork_id
  enable_l4_ilb_subsetting = true
  datapath_provider        = "ADVANCED_DATAPATH"

  workload_identity_config {
    workload_pool = "${var.google_project_id}.svc.id.goog"
  }

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  private_cluster_config {
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    enable_private_endpoint = var.enable_private_endpoint
    enable_private_nodes    = true
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks_cidr_blocks
      content {
        cidr_block   = cidr_blocks.value
        display_name = "authorized"
      }
    }
  }

  ip_allocation_policy {
    stack_type                    = "IPV4_IPV6"
    services_secondary_range_name = var.services_secondary_range_name
    cluster_secondary_range_name  = var.pods_secondary_range_name
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  resource_labels = var.labels

  remove_default_node_pool = true
  initial_node_count       = 1
  # Set `deletion_protection` to `true` will ensure that one cannot
  # accidentally delete this instance by use of Terraform.
  deletion_protection = var.deletion_protection

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z]([a-z0-9-]{0,38}[a-z0-9])?$", local.gke_cluster_name))
      error_message = "The derived GKE cluster name '${local.gke_cluster_name}' violates GKE's rules: at most 40 characters of lowercase letters, digits, and hyphens, starting with a letter and not ending with a hyphen. Shorten project_name_prefix."
    }
  }
}

