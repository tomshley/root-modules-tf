data "google_secret_manager_secret_version" "db" {
  count   = var.db_password == null ? 1 : 0
  project = var.project_id
  secret  = var.db_secret_id
}

data "google_secret_manager_secret_version" "admin" {
  count   = var.admin_password == null && var.admin_secret_id != null ? 1 : 0
  project = var.project_id
  secret  = var.admin_secret_id
}

locals {
  resolved_db_password = var.db_password != null ? var.db_password : jsondecode(data.google_secret_manager_secret_version.db[0].secret_data)["password"]
  resolved_admin_password = var.admin_password != null ? var.admin_password : (
    var.admin_secret_id != null ? jsondecode(data.google_secret_manager_secret_version.admin[0].secret_data)["password"] : null
  )
}

module "keycloak" {
  source = "../k8s-keycloak"

  release_name              = var.release_name
  namespace                 = var.namespace
  create_namespace          = var.create_namespace
  chart_version             = var.chart_version
  image_tag                 = var.image_tag
  db_endpoint               = var.db_endpoint
  db_port                   = var.db_port
  db_name                   = var.db_name
  db_user                   = var.db_user
  db_password               = local.resolved_db_password
  admin_user                = var.admin_user
  admin_password            = local.resolved_admin_password
  realm_json_path           = var.realm_json_path
  service_port              = var.service_port
  service_type              = var.service_type
  replicas                  = var.replicas
  pod_annotations           = var.pod_annotations
  labels                    = var.labels
  resources_requests_cpu    = var.resources_requests_cpu
  resources_requests_memory = var.resources_requests_memory
  resources_limits_cpu      = var.resources_limits_cpu
  resources_limits_memory   = var.resources_limits_memory
  helm_timeout              = var.helm_timeout
  extra_helm_values         = var.extra_helm_values
}
