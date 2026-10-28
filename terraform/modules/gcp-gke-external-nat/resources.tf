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

resource "google_compute_router" "external_static_ip_router" {
  project = var.project_id
  name    = "${var.project_name_prefix}-gke-external-nat-router"
  network = var.google_compute_network_id
  region  = var.google_compute_subnetwork_region
}


module "external_static_nat_config" {
  depends_on                         = [google_compute_router.external_static_ip_router]
  source                             = "terraform-google-modules/cloud-nat/google"
  version                            = "~> 5.0"
  project_id                         = var.project_id
  region                             = var.google_compute_subnetwork_region
  router                             = google_compute_router.external_static_ip_router.name
  name                               = "${var.project_name_prefix}-gke-external-nat-config"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
