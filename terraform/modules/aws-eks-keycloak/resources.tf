###############################################################################
# Keycloak — Helm Release
#
# Installs Keycloak into an existing EKS cluster using the Bitnami Helm chart.
# Database credentials are injected via Kubernetes ExternalSecret or init
# container from Secrets Manager ARN — never plaintext in Helm values.
#
# Consumers must configure the Helm and Kubernetes providers with EKS cluster
# credentials before calling this module.
###############################################################################

# --- Kubernetes Secret for DB credentials (ExternalSecret placeholder) ---
#
# In production, consumers should use ExternalSecretsOperator or CSI Secrets
# Store Driver to sync from Secrets Manager. This module creates a placeholder
# Kubernetes secret that the consumer's external-secrets controller populates
# from var.db_secret_arn. The Helm release references this secret by name.

resource "kubernetes_namespace" "keycloak" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = local.common_labels
  }
}

locals {
  namespace        = var.create_namespace ? kubernetes_namespace.keycloak[0].metadata[0].name : var.namespace
  realm_import      = var.realm_json_path != null
  realm_content_hash = local.realm_import ? sha256(file(var.realm_json_path)) : null
  image_tag_values   = var.keycloak_image_tag != null ? { image = { tag = var.keycloak_image_tag } } : {}
  common_labels = merge({
    "app.kubernetes.io/managed-by" = "terraform"
    "app.kubernetes.io/part-of"    = "keycloak"
    "eks.amazonaws.com/cluster"    = var.cluster_name
  }, var.tags)
}

resource "kubernetes_secret" "db_credentials" {
  metadata {
    name      = "keycloak-db-credentials"
    namespace = local.namespace
    labels    = local.common_labels
    annotations = {
      "secrets-manager/arn" = var.db_secret_arn
    }
  }

  # When var.db_password is provided, the secret is populated with real
  # credentials and the Helm release can connect on first apply. When null,
  # placeholder values are written and ExternalSecretsOperator or CSI Secrets
  # Store Driver syncs actual credentials from the Secrets Manager ARN
  # annotated above.
  data = {
    db-user     = var.db_user
    db-password = var.db_password != null ? var.db_password : "placeholder-sync-from-secrets-manager"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_secret" "admin_credentials" {
  metadata {
    name      = "keycloak-admin-credentials"
    namespace = local.namespace
    labels    = local.common_labels
    annotations = {
      "secrets-manager/arn" = var.admin_secret_arn
    }
  }

  data = {
    admin-password = var.admin_password != null ? var.admin_password : "placeholder-sync-from-secrets-manager"
  }

  lifecycle {
    ignore_changes = [data]
  }
}

resource "kubernetes_config_map" "realm_import" {
  count = local.realm_import ? 1 : 0

  metadata {
    name      = "keycloak-realm-import"
    namespace = local.namespace
    labels    = local.common_labels
  }

  data = {
    "realm.json" = file(var.realm_json_path)
  }
}

resource "helm_release" "keycloak" {
  name             = "keycloak"
  namespace        = local.namespace
  create_namespace = false
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = var.keycloak_chart_version

  values = [
    yamlencode(merge({
      replicaCount = var.replicas
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
    } : {}))
  ]

  depends_on = [
    kubernetes_secret.db_credentials,
    kubernetes_secret.admin_credentials,
  ]

  timeout = var.helm_timeout
  wait    = true
}
