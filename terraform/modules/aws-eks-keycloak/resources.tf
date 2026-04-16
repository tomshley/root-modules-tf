###############################################################################
# Keycloak — Helm Release
#
# Installs Keycloak into an existing EKS cluster using the Bitnami Helm chart.
# DB and admin passwords are resolved from Secrets Manager at plan time when
# not explicitly provided — no ExternalSecretsOperator required for first
# apply. ignore_changes on K8s secret data preserves ESO-managed rotation.
#
# Consumers must configure the Helm and Kubernetes providers with EKS cluster
# credentials before calling this module.
###############################################################################

# --- Kubernetes Secret for DB credentials ---
#
# When var.db_password is provided it is used directly. When null, the module
# resolves the real password from Secrets Manager (var.db_secret_arn) at plan
# time — no ExternalSecretsOperator required. ignore_changes on data prevents
# Terraform from overwriting ESO-managed rotations once the secret exists.

# --- Resolve credentials from Secrets Manager when not explicitly provided ---
#
# This eliminates the ExternalSecretsOperator dependency for first-apply
# bootstrap. The data sources are only created when the corresponding
# password variable is null.

data "aws_secretsmanager_secret_version" "db" {
  count     = var.db_password == null ? 1 : 0
  secret_id = var.db_secret_arn
}

data "aws_secretsmanager_secret_version" "admin" {
  count     = var.admin_password == null && var.admin_secret_arn != null ? 1 : 0
  secret_id = var.admin_secret_arn
}

check "admin_credentials_provided" {
  assert {
    condition     = var.admin_password != null || var.admin_secret_arn != null
    error_message = "Either admin_password or admin_secret_arn must be provided. Without both, Keycloak would start with no usable admin credentials."
  }
}

locals {
  resolved_db_password    = var.db_password != null ? var.db_password : jsondecode(data.aws_secretsmanager_secret_version.db[0].secret_string)["password"]
  resolved_admin_password = var.admin_password != null ? var.admin_password : (
    var.admin_secret_arn != null ? jsondecode(data.aws_secretsmanager_secret_version.admin[0].secret_string)["password"] : null
  )
}

resource "kubernetes_namespace" "keycloak" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

locals {
  namespace          = var.create_namespace ? kubernetes_namespace.keycloak[0].metadata[0].name : var.namespace
  realm_import       = var.realm_json_path != null
  realm_content      = local.realm_import ? file(var.realm_json_path) : null
  realm_content_hash = local.realm_import ? sha256(local.realm_content) : null
  image_tag_values   = var.keycloak_image_tag != null ? { image = { tag = var.keycloak_image_tag } } : {}
  service_host = "${var.release_name}.${local.namespace}.svc.cluster.local"
  port_suffix  = var.service_port != 80 ? ":${var.service_port}" : ""
  common_labels = merge({
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "keycloak"
    "eks.amazonaws.com/cluster"    = var.cluster_name
  }, var.tags)
}

resource "kubernetes_secret" "db_credentials" {
  metadata {
    name      = "${var.release_name}-db-credentials"
    namespace = local.namespace
    labels    = local.common_labels
    annotations = {
      "secrets-manager/arn" = var.db_secret_arn
    }
  }

  data = {
    db-password = local.resolved_db_password
  }

  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_secret" "admin_credentials" {
  metadata {
    name      = "${var.release_name}-admin-credentials"
    namespace = local.namespace
    labels    = local.common_labels
    annotations = {
      "secrets-manager/arn" = var.admin_secret_arn
    }
  }

  data = {
    admin-password = local.resolved_admin_password
  }

  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_config_map" "realm_import" {
  count = local.realm_import ? 1 : 0

  metadata {
    name      = "${var.release_name}-realm-import"
    namespace = local.namespace
    labels    = local.common_labels
  }

  data = {
    "realm.json" = local.realm_content
  }
}

resource "helm_release" "keycloak" {
  name             = var.release_name
  namespace        = local.namespace
  create_namespace = false
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = var.keycloak_chart_version

  values = concat([
    yamlencode(merge({
      fullnameOverride = var.release_name
      replicaCount     = var.replicas
      auth = {
        adminUser         = var.admin_user
        existingSecret    = kubernetes_secret.admin_credentials.metadata[0].name
        passwordSecretKey = "admin-password"
      }
      externalDatabase = {
        host     = var.db_endpoint
        port     = var.db_port
        user     = var.db_user
        database = var.db_name
        existingSecret            = kubernetes_secret.db_credentials.metadata[0].name
        existingSecretPasswordKey  = "db-password"
      }
      postgresql = {
        enabled = false
      }
      service = {
        type = var.service_type
        ports = {
          http = var.service_port
        }
      }
      resources = {
        requests = {
          cpu    = var.resources_requests_cpu
          memory = var.resources_requests_memory
        }
        limits = {
          cpu    = var.resources_limits_cpu
          memory = var.resources_limits_memory
        }
      }
      keycloakConfigCli = local.realm_import ? {
        enabled = true
        existingConfigmap = kubernetes_config_map.realm_import[0].metadata[0].name
      } : {
        enabled = false
      }
    },
    local.image_tag_values,
    local.realm_import ? {
      podAnnotations = {
        "checksum/realm-config" = local.realm_content_hash
      }
    } : {})),
  ], var.extra_helm_values)

  depends_on = [
    kubernetes_secret.db_credentials,
    kubernetes_secret.admin_credentials,
  ]

  timeout = var.helm_timeout
  wait    = true
}
