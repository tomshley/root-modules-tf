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

# Kubernetes RBAC administration is a custom role by necessity: every
# predefined role that manages namespaced RBAC objects also manages the
# cluster itself, and a deploy identity must not carry cluster lifecycle.
locals {
  kubernetes_rbac_admin_role_id = coalesce(
    var.kubernetes_rbac_admin_role_id,
    "${replace(var.service_account_id, "-", "_")}_rbac_admin"
  )
}

resource "google_project_iam_custom_role" "kubernetes_rbac_admin" {
  count = var.kubernetes_rbac_admin ? 1 : 0

  project     = var.project_id
  role_id     = local.kubernetes_rbac_admin_role_id
  title       = "CI Kubernetes RBAC Administration"
  description = "Namespaced Role and RoleBinding administration for a CI deploy service account. Grants no cluster-lifecycle permission."

  # Kubernetes RBAC privilege-escalation prevention requires more than the
  # CRUD verbs: creating a Role that grants permissions the caller does not
  # hold needs container.roles.escalate, and creating a RoleBinding that
  # references a Role needs container.roles.bind (GCP attaches the bind verb
  # to the role resource, not to the binding).
  permissions = [
    "container.roles.bind",
    "container.roles.create",
    "container.roles.delete",
    "container.roles.escalate",
    "container.roles.get",
    "container.roles.list",
    "container.roles.update",
    "container.roleBindings.create",
    "container.roleBindings.delete",
    "container.roleBindings.get",
    "container.roleBindings.list",
    "container.roleBindings.update",
  ]
}

resource "google_project_iam_member" "ci_deploy_rbac_admin" {
  count = var.kubernetes_rbac_admin ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.kubernetes_rbac_admin[0].name
  member  = "serviceAccount:${google_service_account.ci_deploy.email}"
}
