locals {
  gke_service_account_id = lower("${var.project_name_prefix}-${var.google_organization_id}")
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
  name           = "${var.project_name_prefix}-standard-cluster"
  project        = var.google_project_id
  location       = var.google_region
  node_locations = [var.google_region_zone]

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
}

