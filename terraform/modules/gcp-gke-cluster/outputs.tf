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

output "google_project_id" {
  value = var.google_project_id
}

output "google_project_name_prefix" {
  value = var.project_name_prefix
}

output "google_compute_network_gke_network_id" {
  value = var.google_compute_network_id
}

output "google_container_cluster_gke_cluster_name" {
  value = google_container_cluster.gke_cluster.name
}

output "google_service_account_gke_service_account_id" {
  value = google_service_account.gke_service_account.account_id
}

output "google_compute_subnetwork_region" {
  value = var.google_region
}

output "google_compute_subnetwork_id" {
  value = var.google_compute_subnetwork_id
}

output "google_container_cluster_gke_cluster_self_link" {
  value = google_container_cluster.gke_cluster.self_link
}

output "google_container_cluster_gke_cluster_location" {
  value = google_container_cluster.gke_cluster.location
}

output "google_container_cluster_gke_cluster_endpoint" {
  value = google_container_cluster.gke_cluster.endpoint
}

output "google_container_cluster_gke_cluster_ca_certificate" {
  value     = google_container_cluster.gke_cluster.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "google_service_account_gke_service_account_email" {
  value = google_service_account.gke_service_account.email
}
