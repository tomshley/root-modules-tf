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

resource "google_compute_network" "gke_network" {
  project = var.project_id
  name    = "${var.project_name_prefix}-network"

  auto_create_subnetworks  = false
  enable_ula_internal_ipv6 = true
}

resource "google_compute_global_address" "private_services" {
  project       = var.project_id
  name          = "${var.project_name_prefix}-private-services"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = var.private_services_prefix_length
  network       = google_compute_network.gke_network.id
}

resource "google_service_networking_connection" "private_services" {
  network                 = google_compute_network.gke_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services.name]
}

resource "google_compute_subnetwork" "gke_subnet" {
  project = var.project_id
  name    = "${var.project_name_prefix}-subnetwork"

  ip_cidr_range = var.subnet_cidr
  region        = var.region

  stack_type       = "IPV4_IPV6"
  ipv6_access_type = var.ipv6_access_type
  network          = google_compute_network.gke_network.id

  secondary_ip_range {
    range_name    = "${var.project_name_prefix}-subnetwork-services-range"
    ip_cidr_range = var.services_cidr
  }

  secondary_ip_range {
    range_name    = "${var.project_name_prefix}-subnetwork-pod-ranges"
    ip_cidr_range = var.pods_cidr
  }
}
