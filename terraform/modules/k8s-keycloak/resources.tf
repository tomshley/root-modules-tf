# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

resource "kubernetes_namespace" "keycloak" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name   = var.namespace
    labels = var.labels
  }
}

locals {
  resolved_namespace = var.create_namespace ? kubernetes_namespace.keycloak[0].metadata[0].name : var.namespace
  realm_import       = var.realm_json_path != null
  realm_content      = local.realm_import ? file(var.realm_json_path) : null
  realm_content_hash = local.realm_import ? sha256(local.realm_content) : null
  image_tag_values   = var.image_tag != null ? { image = { tag = var.image_tag } } : {}
  pod_annotations = merge(
    var.pod_annotations,
    local.realm_import ? { "checksum/realm-config" = local.realm_content_hash } : {},
  )
  service_host = "${var.release_name}.${local.resolved_namespace}.svc.cluster.local"
  port_suffix  = var.service_port != 80 ? ":${var.service_port}" : ""
}

resource "kubernetes_secret" "db_credentials" {
  metadata {
    name        = "${var.release_name}-db-credentials"
    namespace   = local.resolved_namespace
    labels      = var.labels
    annotations = var.db_secret_annotations
  }

  data = { db-password = var.db_password }

  lifecycle {
    ignore_changes = [data]

    precondition {
      condition     = var.db_password != null
      error_message = "db_password must be supplied."
    }
  }
}

resource "kubernetes_secret" "admin_credentials" {
  metadata {
    name        = "${var.release_name}-admin-credentials"
    namespace   = local.resolved_namespace
    labels      = var.labels
    annotations = var.admin_secret_annotations
  }

  data = { admin-password = var.admin_password }

  lifecycle {
    ignore_changes = [data]

    precondition {
      condition     = var.admin_password != null
      error_message = "admin_password must be supplied."
    }
  }
}

resource "kubernetes_config_map" "realm_import" {
  count = local.realm_import ? 1 : 0

  metadata {
    name      = "${var.release_name}-realm-import"
    namespace = local.resolved_namespace
    labels    = var.labels
  }

  data = { "realm.json" = local.realm_content }
}

resource "helm_release" "keycloak" {
  name             = var.release_name
  namespace        = local.resolved_namespace
  create_namespace = false
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "keycloak"
  version          = var.chart_version

  values = concat([yamlencode(merge({
    fullnameOverride = var.release_name
    replicaCount     = var.replicas
    auth = {
      adminUser         = var.admin_user
      existingSecret    = kubernetes_secret.admin_credentials.metadata[0].name
      passwordSecretKey = "admin-password"
    }
    externalDatabase = {
      host                      = var.db_endpoint
      port                      = var.db_port
      user                      = var.db_user
      database                  = var.db_name
      existingSecret            = kubernetes_secret.db_credentials.metadata[0].name
      existingSecretPasswordKey = "db-password"
    }
    postgresql = { enabled = false }
    service = {
      type  = var.service_type
      ports = { http = var.service_port }
    }
    resources = {
      requests = { cpu = var.resources_requests_cpu, memory = var.resources_requests_memory }
      limits   = { cpu = var.resources_limits_cpu, memory = var.resources_limits_memory }
    }
    keycloakConfigCli = local.realm_import ? {
      enabled           = true
      existingConfigmap = kubernetes_config_map.realm_import[0].metadata[0].name
      } : {
      enabled = false
    }
    }, local.image_tag_values, length(local.pod_annotations) > 0 ? {
    podAnnotations = local.pod_annotations
  } : {}))], var.extra_helm_values)

  depends_on = [kubernetes_secret.db_credentials, kubernetes_secret.admin_credentials]
  timeout    = var.helm_timeout
  wait       = true
}
