resource "google_service_account" "gke_service_account" {
  account_id = "${var.project_name_prefix}-${var.google_organization_id}"
  project    = var.google_project_id
}

resource "google_compute_network" "gke_network" {
  name       = "${var.project_name_prefix}-network"

  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "gke_subnet" {
  depends_on = [google_compute_network.gke_network]
  name       = "${var.project_name_prefix}-subnetwork"

  ip_cidr_range = "10.0.0.0/16"
  region        = var.google_region

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL" # Change to "EXTERNAL" if creating an external loadbalancer
  # ipv6_access_type = "EXTERNAL" # Change to "EXTERNAL" if creating an external loadbalancer

  network = google_compute_network.gke_network.id
  secondary_ip_range {
    range_name    = "${var.project_name_prefix}-subnetwork-services-range"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "${var.project_name_prefix}-subnetwork-pod-ranges"
    ip_cidr_range = "10.124.0.0/14"
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

  private_cluster_config {
    master_ipv4_cidr_block  = "172.16.0.0/28"
    enable_private_endpoint = false
    enable_private_nodes    = true
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

  remove_default_node_pool = true
  initial_node_count       = 1
  # Set `deletion_protection` to `true` will ensure that one cannot
  # accidentally delete this instance by use of Terraform.
  deletion_protection = false
}

