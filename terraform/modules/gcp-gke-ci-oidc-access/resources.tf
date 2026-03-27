resource "google_iam_workload_identity_pool" "ci" {
  project                   = var.project_id
  workload_identity_pool_id = var.pool_id
  display_name              = coalesce(var.pool_display_name, var.pool_id)
}

resource "google_iam_workload_identity_pool_provider" "ci" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.ci.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = coalesce(var.provider_display_name, var.provider_id)

  attribute_mapping   = var.attribute_mapping
  attribute_condition = var.attribute_condition

  oidc {
    issuer_uri        = var.oidc_issuer_url
    allowed_audiences = length(var.oidc_allowed_audiences) > 0 ? var.oidc_allowed_audiences : null
  }
}

resource "google_service_account" "ci_deploy" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = coalesce(var.service_account_display_name, var.service_account_id)
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.ci_deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.ci.name}/*"
}

resource "google_project_iam_member" "ci_deploy" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.ci_deploy.email}"
}
