output "release_name" { value = helm_release.karpenter.name }
output "release_namespace" { value = helm_release.karpenter.namespace }
output "release_version" { value = helm_release.karpenter.version }
output "node_class_network_tags" { value = var.node_network_tags }
output "node_service_account_email" { value = var.node_service_account_email }
