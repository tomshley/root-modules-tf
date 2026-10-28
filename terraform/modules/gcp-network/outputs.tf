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

output "network_id" {
  value = google_compute_network.gke_network.id
}

output "subnetwork_id" {
  value = google_compute_subnetwork.gke_subnet.id
}

output "subnetwork_region" {
  value = google_compute_subnetwork.gke_subnet.region
}

output "services_secondary_range_name" {
  value = google_compute_subnetwork.gke_subnet.secondary_ip_range[0].range_name
}

output "pods_secondary_range_name" {
  value = google_compute_subnetwork.gke_subnet.secondary_ip_range[1].range_name
}

output "private_services_connection_id" {
  value = google_service_networking_connection.private_services.id
}

output "node_network_tags" {
  value = var.node_network_tags
}

