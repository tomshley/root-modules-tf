resource "google_compute_router" "external-static-ip-router" {
  project = var.project_id
  name    = "${var.project_name}-gke-external-nat-router"
  network = var.google_compute_network_id
  region  = var.google_region
}

module "external-static-ip-nat" {
  depends_on = [
    google_compute_router.external-static-ip-router
  ]
  source                             = "terraform-google-modules/cloud-nat/google"
  version                            = "~> 5.3.0"
  project_id                         = var.project_id
  region                             = var.google_region
  router                             = google_compute_router.external-static-ip-router.name
  name                               = "${var.project_name}-gke-external-nat"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
