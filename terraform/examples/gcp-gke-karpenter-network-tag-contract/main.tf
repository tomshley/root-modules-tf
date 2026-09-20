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

module "network" {
  source = "../../modules/gcp-network"

  project_id          = var.project_id
  project_name_prefix = "example"
  region              = var.region
  node_network_tags   = ["allow-egress", "allow-observability"]
}

module "karpenter_prereqs" {
  source = "../../modules/gcp-karpenter-prereqs"

  project_id                 = var.project_id
  project_name_prefix        = "example"
  node_service_account_email = var.node_service_account_email
}

module "karpenter" {
  source = "../../modules/gcp-karpenter-controller"

  project_id                              = var.project_id
  cluster_name                            = var.cluster_name
  cluster_location                        = var.region
  controller_google_service_account_email = module.karpenter_prereqs.controller_google_service_account_email
  node_service_account_email              = module.karpenter_prereqs.node_service_account_email
  node_network_tags                       = module.network.node_network_tags
}

check "karpenter_network_tag_contract" {
  assert {
    condition     = setequals(module.network.node_network_tags, module.karpenter.node_class_network_tags)
    error_message = "Every network tag required by gcp-network must be copied into each Karpenter GCENodeClass spec.networkTags."
  }
}

output "gcenodeclass_network_tags" {
  value = module.karpenter.node_class_network_tags
}
