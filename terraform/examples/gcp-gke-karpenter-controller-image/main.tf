variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "cluster_name" {
  type    = string
  default = "example-gke-standard-cluster"
}

variable "node_service_account_email" {
  type = string
}

variable "image_pull_secret_name" {
  type    = string
  default = null
}

module "karpenter_prereqs" {
  source = "../../modules/gcp-karpenter-prereqs"

  project_id                 = var.project_id
  project_name_prefix        = "example"
  node_service_account_email = var.node_service_account_email
}

# gcp-gke-cluster builds dual-stack (IPV4_IPV6) clusters, and the upstream
# controller image provisions IPv4-only node NICs — on such a cluster GKE's
# IPAM never publishes podCIDRs, so a Karpenter node can never reach Ready.
# use_patched_dual_stack_image resolves the vendored patched build for the
# pinned chart version; image_pull_secrets names the existing
# namespace-local Secret carrying the registry credential when the vendored
# image is not pulled from a registry the node service account already reads.
# controller_image remains the escape hatch for an arbitrary build.
module "karpenter" {
  source = "../../modules/gcp-karpenter-controller"

  project_id                              = var.project_id
  cluster_name                            = var.cluster_name
  cluster_location                        = var.region
  controller_google_service_account_email = module.karpenter_prereqs.controller_google_service_account_email
  node_service_account_email              = module.karpenter_prereqs.node_service_account_email
  use_patched_dual_stack_image            = true
  image_pull_secrets                      = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]
}
