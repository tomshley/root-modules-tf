data "google_container_cluster" "default_cluster" {
  name = var.google_container_cluster_name
}
data "google_service_account" "default_service_account" {
  account_id = var.google_service_account_default_account_id
}

resource "google_container_node_pool" "containerized-multithreaded-service-pool" {
  depends_on = [
    data.google_service_account.default_service_account,
    data.google_container_cluster.default_cluster
  ]
  name     = "${var.project_name_prefix}-pool-containr-multhrd"
  location = var.google_region
  cluster = data.google_container_cluster.default_cluster.name

  # initial node count
  node_count = 1

  autoscaling {
    min_node_count  = 1
    max_node_count  = 5
    location_policy = "ANY"
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # https://github.com/hashicorp/terraform-provider-google/issues/15848#issuecomment-2616355921
  lifecycle {
    ignore_changes = [
      node_config[0].resource_labels["goog-gke-node-pool-provisioning-model"]
    ]
  }

  node_config {
    preemptible  = false
    spot         = false
    machine_type = "t2d-standard-2"
    disk_type    = "pd-standard"
    disk_size_gb = 30

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
    #
    #   # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    #   service_account = data.google_service_account.default_service_account.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}

################################################################
# For reference if we want dedicated pools and taints:
################################################################
# resource "google_container_node_pool" "default" {
#   depends_on = [
#     data.google_container_cluster.default_cluster,
#     data.google_service_account.default_service_account
#   ]
#   name       = "${var.project_name}-nodepool-default"
#   location   = var.google_region
#   cluster    = data.google_container_cluster.default_cluster.name
#   node_count = 1
#
#   autoscaling {
#     min_node_count  = 0
#     max_node_count  = 1
#     location_policy = "ANY"
#   }
#
#   management {
#     auto_repair  = true
#     auto_upgrade = true
#   }
#
#   node_config {
#     preemptible  = false
#     spot         = true
#     machine_type = "e2-medium"
#     disk_type    = "pd-standard"
#     disk_size_gb = 20
#     #
#     #   # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
#     #   service_account = data.google_service_account.default_service_account.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform"
#     ]
#   }
# }

# resource "google_container_node_pool" "service-contact" {
#   depends_on = [
#     data.google_service_account.default_service_account,
#     data.google_container_cluster.default_cluster,
#     google_container_node_pool.default
#   ]
#   name       = "${var.project_name}-pool-contactsvc"
#   location   = var.google_region
#   cluster    = data.google_container_cluster.default_cluster.name
#   node_count = 1
#
#   autoscaling {
#     min_node_count  = 1
#     max_node_count  = 2
#     location_policy = "ANY"
#   }
#
#   management {
#     auto_repair  = true
#     auto_upgrade = true
#   }
#
#   node_config {
#     preemptible  = false
#     spot         = false
#     machine_type = "t2d-standard-1"
#     disk_type    = "pd-standard"
#     disk_size_gb = 10
#     #
#     #   # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
#     #   service_account = data.google_service_account.default_service_account.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform"
#     ]
#
#     taint {
#       effect = "NO_SCHEDULE"
#       key    = "${var.project_name}-pooltaintdedicated"
#       value  = "${var.project_name}-pool-contactsvc-taint"
#     }
#   }
# }

# resource "google_container_node_pool" "service-web" {
#   depends_on = [
#     data.google_service_account.default_service_account,
#     data.google_container_cluster.default_cluster,
#     google_container_node_pool.default,
#     google_container_node_pool.service-contact
#   ]
#   name       = "${var.project_name}-pool-websvr"
#   location   = var.google_region
#   cluster    = data.google_container_cluster.default_cluster.name
#   node_count = 1
#
#   autoscaling {
#     min_node_count  = 1
#     max_node_count  = 2
#     location_policy = "ANY"
#   }
#
#   management {
#     auto_repair  = true
#     auto_upgrade = true
#   }
#
#   node_config {
#     preemptible  = false
#     spot         = false
#     machine_type = "t2d-standard-1"
#     disk_type    = "pd-standard"
#     disk_size_gb = 10
#     #
#     #   # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
#     #   service_account = data.google_service_account.default_service_account.email
#     oauth_scopes = [
#       "https://www.googleapis.com/auth/cloud-platform"
#     ]
#
#     taint {
#       effect = "NO_SCHEDULE"
#       key    = "${var.project_name}-pooltaintdedicated"
#       value  = "${var.project_name}-pool-websvr-taint"
#     }
#   }
# }

