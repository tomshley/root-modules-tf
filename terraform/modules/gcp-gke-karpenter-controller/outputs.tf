output "google_service_account_email" {
  value = var.controller_google_service_account_email
}

output "release_name" {
  value = module.karpenter.release_name
}

output "release_namespace" {
  value = module.karpenter.release_namespace
}

output "release_version" {
  value = module.karpenter.release_version
}

output "node_class_network_tags" {
  value = module.karpenter.node_class_network_tags
}

output "node_service_account_email" {
  value = module.karpenter.node_service_account_email
}
