variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "cluster_name" {
  type        = string
  description = "GKE cluster name."
}

variable "cluster_location" {
  type        = string
  description = "GKE cluster location used for instance-type discovery. Accepts a region or a zone — the controller derives the compute region from it."

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+(-[a-z])?$", var.cluster_location))
    error_message = "cluster_location must be a GCP region (for example us-central1) or zone (for example us-central1-a)."
  }
}

variable "node_location" {
  type        = string
  default     = null
  description = "Exact GKE cluster location used to address the cluster in the provider's GKE node-pool API paths — not a node-placement choice. Normally omit it: the controller defaults it to cluster_location, which is correct both for a regional cluster (whose location is its region) and for a zonal cluster whose cluster_location is its zone. Set it only when cluster_location is a region but the cluster itself is zonal."

  validation {
    condition     = var.node_location == null || can(regex("^[a-z]+-[a-z]+[0-9]+(-[a-z])?$", var.node_location))
    error_message = "node_location must be null or a GCP region (for example us-central1) or zone (for example us-central1-a)."
  }
}

variable "namespace" {
  type        = string
  default     = "karpenter-system"
  description = "Namespace where the Karpenter chart creates its Kubernetes ServiceAccount."
}

variable "kubernetes_service_account_name" {
  type        = string
  default     = "karpenter"
  description = "Kubernetes ServiceAccount name managed by the Karpenter Helm chart."
}

variable "controller_google_service_account_email" {
  type        = string
  description = "Google service-account email created by gcp-karpenter-prereqs."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.iam\\.gserviceaccount\\.com$", var.controller_google_service_account_email))
    error_message = "controller_google_service_account_email must be a valid Google service-account email."
  }
}

variable "node_service_account_email" {
  type        = string
  description = "Google service account attached to Karpenter-provisioned GKE nodes."

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.iam\\.gserviceaccount\\.com$", var.node_service_account_email))
    error_message = "node_service_account_email must be a valid Google service-account email."
  }
}

variable "node_network_tags" {
  type        = set(string)
  default     = []
  description = "Explicit network tags to place in each GCENodeClass spec.networkTags."
}

variable "create_namespace" {
  type        = bool
  default     = true
  description = "Whether Helm creates the Karpenter namespace."
}

variable "extra_helm_values" {
  type        = list(string)
  default     = []
  description = "Additional Helm values appended after module-managed values."
}

variable "use_patched_dual_stack_image" {
  type        = bool
  default     = false
  description = "Use the patched controller image that sets node NIC stackType from the cluster's IP allocation policy. Required for Karpenter nodes to reach Ready on dual-stack (IPV4_IPV6) clusters — the upstream controller provisions IPv4-only NICs, so GKE's IPAM never publishes podCIDRs. Resolves the vendored build for the pinned chart version; mutually exclusive with controller_image."
}

variable "controller_image" {
  type = object({
    repository = string
    tag        = string
  })
  default     = null
  description = "Explicit controller image override for the chart's controller.image.repository and .tag. Null keeps the upstream release image (or the vendored dual-stack build when use_patched_dual_stack_image is set)."

  validation {
    condition     = var.controller_image == null || (length(var.controller_image.repository) > 0 && length(var.controller_image.tag) > 0)
    error_message = "controller_image.repository and controller_image.tag must both be non-empty when controller_image is set."
  }
}

variable "image_pull_secrets" {
  type        = list(string)
  default     = []
  description = "Names of existing Kubernetes Secrets in the controller namespace rendered as the chart's top-level imagePullSecrets. Required when controller_image lives in a registry the node service account cannot pull — for example a private GitLab container registry behind a read_registry deploy token."
}

variable "helm_timeout_seconds" {
  type        = number
  default     = 300
  description = "Helm wait timeout for the karpenter-crd and karpenter releases. Raise on cold first installs where node provisioning and image pulls exceed the default five minutes."
}

variable "bootstrap_node_pool_name" {
  type        = string
  default     = null
  description = "Existing GKE node pool the controller bootstraps new nodes from. From provider v0.4.0 the controller no longer creates its own template node pools — it discovers an existing RUNNING pool (\"default-pool\", else first alphabetically, else a created \"karpenter-fallback\"). Alphabetical ordering is incidental, not a contract; set this to a pool whose shape you intend nodes to inherit. Leave null to keep upstream discovery."
}
