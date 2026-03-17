resource "google_service_account" "gke_service_account" {
  account_id = "${var.project_name_prefix}-${var.google_organization_id}"
  project    = var.google_project_id
}

resource "google_compute_network" "gke_network" {
  project = var.google_project_id
  name    = "${var.project_name_prefix}-network"

  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "gke_subnet" {
  depends_on = [google_compute_network.gke_network]
  project    = var.google_project_id
  name       = "${var.project_name_prefix}-subnetwork"

  ip_cidr_range = var.subnet_cidr
  region        = var.google_region

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = var.ipv6_access_type

  network = google_compute_network.gke_network.id
  secondary_ip_range {
    range_name    = "${var.project_name_prefix}-subnetwork-services-range"
    ip_cidr_range = var.services_cidr
  }

  secondary_ip_range {
    range_name    = "${var.project_name_prefix}-subnetwork-pod-ranges"
    ip_cidr_range = var.pods_cidr
  }
}

resource "google_container_cluster" "gke_cluster" {
  depends_on = [
    google_service_account.gke_service_account,
    google_compute_network.gke_network,
    google_compute_subnetwork.gke_subnet
  ]
  name           = "${var.project_name_prefix}-standard-cluster"
  project        = var.google_project_id
  location       = var.google_region
  node_locations = [var.google_region_zone]

  network                  = google_compute_network.gke_network.id
  subnetwork               = google_compute_subnetwork.gke_subnet.id
  enable_l4_ilb_subsetting = true
  datapath_provider        = "ADVANCED_DATAPATH"

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  private_cluster_config {
    master_ipv4_cidr_block  = var.master_ipv4_cidr_block
    enable_private_endpoint = false
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
    services_secondary_range_name = google_compute_subnetwork.gke_subnet.secondary_ip_range[0].range_name
    cluster_secondary_range_name  = google_compute_subnetwork.gke_subnet.secondary_ip_range[1].range_name
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

