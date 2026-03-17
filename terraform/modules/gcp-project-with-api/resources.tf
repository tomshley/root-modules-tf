module "gcp-project" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0.0"

  random_project_id       = false
  name                    = var.google_project_id
  org_id                  = var.google_organization_id
  billing_account         = var.google_billing_account
  default_service_account = "keep"
  labels                  = var.labels

  activate_api_identities = [
  ]

  deletion_policy = "DELETE"
}

module "gcp-project-enable-api" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "~> 18.0.0"
  project_id                  = module.gcp-project.project_id
  depends_on                  = [module.gcp-project]
  disable_services_on_destroy = true
  activate_apis = [
    "iamcredentials.googleapis.com",
    "container.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "compute.googleapis.com"
  ]
}
