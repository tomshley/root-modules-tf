output "controller_google_service_account_email" { value = module.workload_identity.google_service_account_email }
output "kubernetes_service_account_annotation" { value = module.workload_identity.kubernetes_service_account_annotation }
output "node_service_account_email" { value = var.node_service_account_email }
output "controller_role_name" { value = google_project_iam_custom_role.karpenter.name }
