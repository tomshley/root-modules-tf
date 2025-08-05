#
#
# resource "google_container_cluster" "default" {
#   name     = "${var.project_name}-standard-cluster"
#   project  = var.google_project_id
#   location = var.google_region
#   node_locations = [var.google_region_zone]
#
#   network                  = var.google_compute_network_default_id
#   subnetwork               = var.google_compute_subnetwork_default_id
#   enable_l4_ilb_subsetting = true
#   datapath_provider        = "ADVANCED_DATAPATH"
#
#   ip_allocation_policy {
#     stack_type                    = "IPV4_IPV6"
#     services_secondary_range_name = var.google_compute_subnetwork_default_secondary_ip_range_range_name_0
#     cluster_secondary_range_name  = var.google_compute_subnetwork_default_secondary_ip_range_range_name_1
#   }
#
#   maintenance_policy {
#     daily_maintenance_window {
#       start_time = "03:00"
#     }
#   }
#
#   remove_default_node_pool = true
#   initial_node_count       = 1
#   # Set `deletion_protection` to `true` will ensure that one cannot
#   # accidentally delete this instance by use of Terraform.
#   deletion_protection      = false
# }
#


module "gcp-project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0.0"

  random_project_id       = false
  name                    = var.google_project_id
  org_id                  = var.google_organization_id
  billing_account         = var.google_billing_account
  default_service_account = "keep"

  activate_api_identities = [
  ]

  deletion_policy = "DELETE"
}

module "gcp-project-enable-api" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "~> 18.0.0"
  project_id                  = module.gcp-project.project_id
  depends_on = [module.gcp-project]
  disable_services_on_destroy = true
  activate_apis = [
    "iamcredentials.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com"
  ]
}

resource "google_service_account" "default" {
  depends_on = [module.gcp-project-enable-api]
  account_id = "${var.project_name}-${var.google_organization_id}"
  project    = module.gcp-project.project_id
}

resource "google_compute_network" "default" {
  depends_on = [module.gcp-project-enable-api]
  name = "${var.project_name}-network"

  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_subnetwork" "default" {
  depends_on = [google_compute_network.default]
  name = "${var.project_name}-subnetwork"

  ip_cidr_range = "10.0.0.0/16"
  region        = var.google_region

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = "INTERNAL" # Change to "EXTERNAL" if creating an external loadbalancer
  # ipv6_access_type = "EXTERNAL" # Change to "EXTERNAL" if creating an external loadbalancer

  network = google_compute_network.default.id
  secondary_ip_range {
    range_name    = "${var.project_name}-subnetwork-services-range"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "${var.project_name}-subnetwork-pod-ranges"
    ip_cidr_range = "10.124.0.0/14"
  }
}


resource "google_compute_router" "external-static-ip-router" {
  depends_on = [
    module.gcp-project,
    google_compute_network.default
  ]
  project = module.gcp-project.project_id
  name    = "${var.project_name}-external-nat-router"
  network = google_compute_network.default.id
  region  = var.google_region
}

module "external-static-ip-nat" {
  depends_on = [
    module.gcp-project,
    google_compute_router.external-static-ip-router
  ]
  source                             = "terraform-google-modules/cloud-nat/google"
  version                            = "~> 5.3.0"
  project_id                         = module.gcp-project.project_id
  region                             = var.google_region
  router                             = google_compute_router.external-static-ip-router.name
  name                               = "${var.project_name}-external-nat"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_container_cluster" "default" {
  depends_on = [
    module.gcp-project,
    google_service_account.default,
    google_compute_network.default,
    google_compute_subnetwork.default
  ]
  name     = "${var.project_name}-standard-cluster"
  project  = module.gcp-project.project_id
  location = var.google_region
  node_locations = [var.google_region_zone]

  network                  = google_compute_network.default.id
  subnetwork               = google_compute_subnetwork.default.id
  enable_l4_ilb_subsetting = true
  datapath_provider        = "ADVANCED_DATAPATH"

  ip_allocation_policy {
    stack_type                    = "IPV4_IPV6"
    services_secondary_range_name = google_compute_subnetwork.default.secondary_ip_range[0].range_name
    cluster_secondary_range_name  = google_compute_subnetwork.default.secondary_ip_range[1].range_name
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
  deletion_protection      = false
}

