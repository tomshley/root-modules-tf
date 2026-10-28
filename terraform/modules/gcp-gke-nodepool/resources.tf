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

locals {
  pool_location = coalesce(var.google_container_cluster_location, var.google_region)
}

resource "google_container_node_pool" "pool" {
  name     = "${var.project_name_prefix}-pool-${var.pool_name_suffix}"
  location = local.pool_location
  cluster  = var.google_container_cluster_self_link

  initial_node_count = var.initial_node_count

  autoscaling {
    min_node_count  = var.min_node_count
    max_node_count  = var.max_node_count
    location_policy = var.location_policy
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # https://github.com/hashicorp/terraform-provider-google/issues/15848#issuecomment-2616355921
  lifecycle {
    ignore_changes = [
      node_config[0].resource_labels["goog-gke-node-pool-provisioning-model"],
      initial_node_count,
    ]

    precondition {
      condition = try(
        regex("/locations/([^/]+)/clusters/", var.google_container_cluster_self_link)[0] == local.pool_location,
        true,
      )
      error_message = "The node pool location differs from the cluster location in google_container_cluster_self_link; set google_container_cluster_location from the gcp-gke-cluster output google_container_cluster_gke_cluster_location."
    }
  }

  node_config {
    preemptible  = var.preemptible
    spot         = var.spot
    machine_type = var.machine_type
    disk_type    = var.disk_type
    disk_size_gb = var.disk_size_gb

    service_account = var.google_service_account_email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels          = var.labels
    resource_labels = var.labels

    dynamic "taint" {
      for_each = var.taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    # https://github.com/hashicorp/terraform-provider-google/issues/12584#issuecomment-2619971101
    dynamic "kubelet_config" {
      for_each = var.kubelet_config != {} ? [var.kubelet_config] : []
      content {
        cpu_manager_policy   = kubelet_config.value.cpu_manager_policy
        cpu_cfs_quota        = kubelet_config.value.cpu_cfs_quota
        cpu_cfs_quota_period = kubelet_config.value.cpu_cfs_quota_period
        pod_pids_limit       = kubelet_config.value.pod_pids_limit
      }
    }
  }
}
