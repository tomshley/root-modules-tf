
output "google_project_id" {
  value = module.gcp-project.project_id
}

output "project_name_prefix" {
  value = var.project_name_prefix
}

output "google_project_org_id" {
  value = var.google_organization_id
}

output "google_project_billing_account" {
  value = var.google_billing_account
}

