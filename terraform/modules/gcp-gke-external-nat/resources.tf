resource "google_compute_router" "external_static_ip_router" {
  project = var.project_id
  name    = "${var.project_name_prefix}-gke-external-nat-router"
  network = var.google_compute_network_id
  region  = var.google_compute_subnetwork_region
}


module "external_static_nat_config" {
  depends_on = [google_compute_router.external_static_ip_router]
  source                             = "terraform-google-modules/cloud-nat/google"
  version                            = "~> 5.0"
  project_id                         = var.project_id
  region                             = var.google_compute_subnetwork_region
  router                             = google_compute_router.external_static_ip_router.name
  name                               = "${var.project_name_prefix}-gke-external-nat-config"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
