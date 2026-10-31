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

variable "google_organization_id" {
  type = string
}

variable "google_region" {
  type = string
}

variable "google_region_zone" {
  type = string
}

variable "location_mode" {
  type        = string
  default     = "regional"
  description = "Control-plane topology. \"regional\" (default) places the cluster at google_region with nodes in google_region_zone. \"zonal\" places the cluster and its nodes at google_region_zone with a single-zone control plane, which is unavailable during control-plane upgrades and zone outages. Changing this on an existing cluster forces its replacement."

  validation {
    condition     = contains(["regional", "zonal"], var.location_mode)
    error_message = "location_mode must be either \"regional\" or \"zonal\"."
  }
}

variable "google_project_id" {
  type = string
}

variable "project_name_prefix" {
  type = string
}

variable "google_compute_network_id" {
  type        = string
  description = "Network ID from gcp-network."
}

variable "google_compute_subnetwork_id" {
  type        = string
  description = "Subnetwork ID from gcp-network."
}

variable "services_secondary_range_name" {
  type        = string
  description = "Services secondary range name from gcp-network."
}

variable "pods_secondary_range_name" {
  type        = string
  description = "Pods secondary range name from gcp-network."
}

variable "master_ipv4_cidr_block" {
  type        = string
  default     = "172.16.0.0/28"
  description = "Private IP CIDR for GKE control plane"
}

variable "labels" {
  type        = map(string)
  default     = {}
  description = "Additional labels to apply to GKE resources where supported"
}

variable "enable_private_endpoint" {
  type        = bool
  default     = true
  description = "Whether the GKE control plane uses a private endpoint. Public endpoint access requires explicit authorized CIDRs."
}

variable "master_authorized_networks_cidr_blocks" {
  type    = list(string)
  default = []

  validation {
    condition = alltrue([
      for cidr in var.master_authorized_networks_cidr_blocks : can(cidrhost(cidr, 0))
    ]) && (var.enable_private_endpoint || length(var.master_authorized_networks_cidr_blocks) > 0)
    error_message = "master_authorized_networks_cidr_blocks must contain valid CIDRs and cannot be empty when the public endpoint is enabled."
  }

  description = "CIDR blocks allowed to access the GKE control plane when its public endpoint is enabled."
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "managed_prometheus" {
  type        = bool
  default     = null
  description = "Google Cloud Managed Service for Prometheus. Null renders nothing and leaves the cluster's current setting as it is: GKE's default, enabled, for a cluster that never set it, so an existing cluster re-plans to zero changes. False disables it, removing its collectors and their ingestion charges, and the module turns the metric packages off in the same update by setting enable_components to SYSTEM_COMPONENTS, because GKE refuses to disable Managed Prometheus while packages remain enabled; monitoring_components passes them back on resume. True enables it. Returning to null after false keeps it disabled, so a consumer that switches it off, for example while paused, sets true to turn it back on. GKE creates the gmp-critical PriorityClass only while it is enabled, so a consumer removes pods using that class first, as the environment-pause example removes the GKE Karpenter chart's controller, or gives them a class of its own. The AWS modules here provision no managed Prometheus collector; pausing other metrics collectors on either cloud, such as the Grafana Alloy modules, is left to the consumer."
}

variable "monitoring_components" {
  type        = list(string)
  default     = null
  description = "GKE monitoring components: SYSTEM_COMPONENTS plus its metric packages. Null renders nothing and leaves the cluster's components as they are; a list sets exactly those, and an empty list is refused because GKE keeps system monitoring on. With managed_prometheus = false the module sets SYSTEM_COMPONENTS only, because GKE refuses metric packages without Managed Prometheus, and turning Managed Prometheus back on does not restore packages by itself: a consumer resuming passes the packages it wants back here, in the same update. Pass metric packages only while enabling Managed Prometheus or while it is already on: a cluster whose Managed Prometheus is off refuses them, and the module cannot see that when managed_prometheus is null. With managed_prometheus = false the module deliberately refuses every component but SYSTEM_COMPONENTS — control-plane metrics (APISERVER, SCHEDULER, CONTROLLER_MANAGER) included — and drops them while it is off, since GKE sends those through Managed Prometheus too; resuming passes them back like the other packages. The provider compares the list in order and GKE stores its own order, so pass the order a plan of the cluster shows, or every plan shows a reorder."

  validation {
    condition = var.monitoring_components == null || (length(var.monitoring_components) > 0 && alltrue([
      for component in var.monitoring_components : contains([
        "SYSTEM_COMPONENTS", "APISERVER", "SCHEDULER", "CONTROLLER_MANAGER",
        "STORAGE", "HPA", "POD", "DAEMONSET", "DEPLOYMENT", "STATEFULSET",
        "KUBELET", "CADVISOR", "DCGM", "JOBSET",
      ], component)
    ]))
    error_message = "monitoring_components entries must be GKE monitoring components: SYSTEM_COMPONENTS, APISERVER, SCHEDULER, CONTROLLER_MANAGER, STORAGE, HPA, POD, DAEMONSET, DEPLOYMENT, STATEFULSET, KUBELET, CADVISOR, DCGM, JOBSET. An empty list is refused because GKE keeps system monitoring on."
  }
}
