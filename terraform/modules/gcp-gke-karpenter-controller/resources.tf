module "karpenter" {
  source = "../gcp-karpenter-controller"

  project_id                              = var.project_id
  cluster_name                            = var.cluster_name
  cluster_location                        = var.cluster_location
  node_location                           = var.node_location
  namespace                               = var.namespace
  kubernetes_service_account_name         = var.kubernetes_service_account_name
  controller_google_service_account_email = var.controller_google_service_account_email
  node_service_account_email              = var.node_service_account_email
  node_network_tags                       = var.node_network_tags
  create_namespace                        = var.create_namespace
  extra_helm_values                       = var.extra_helm_values
  helm_timeout_seconds                    = var.helm_timeout_seconds
}
