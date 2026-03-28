locals {
  # Confluent API object types — stable across provider v2.x.
  # If Confluent changes API versioning, update these values.
  kafka_cluster_api_version = "cmk/v2"
  kafka_cluster_kind        = "Cluster"
  sr_cluster_api_version    = "srcm/v2"
  sr_cluster_kind           = "Cluster"

  # Strip inherited sensitivity from schema_registry so it can be used in
  # for_each. The value contains only cluster_id and resource_name (IDs/CRNs),
  # not secrets. Sensitivity is inherited when the caller's parent variable
  # (e.g. var.confluent) is marked sensitive.
  sr_configured = nonsensitive(var.schema_registry != null)
  sr_for_each   = local.sr_configured ? { default = nonsensitive(var.schema_registry) } : {}

  # Principal and permission are fixed per plan
  principal  = "User:${confluent_service_account.this.id}"
  permission = "ALLOW"
  host       = "*"

  # Normalize and flatten topic permissions
  normalized_topic_acls = {
    for entry in flatten([
      for index, perm in var.topic_permissions : [
        for op in perm.operations : {
          key           = "TOPIC:${perm.topic}:${perm.pattern_type}:${op}"
          resource_type = "TOPIC"
          resource_name = perm.topic
          pattern_type  = perm.pattern_type
          operation     = op
          principal     = local.principal
          permission    = local.permission
          host          = local.host
        }
      ]
    ]) : entry.key => entry
  }

  # Normalize and flatten group permissions
  normalized_group_acls = {
    for entry in flatten([
      for index, perm in var.group_permissions : [
        for op in perm.operations : {
          key           = "GROUP:${perm.group}:${perm.pattern_type}:${op}"
          resource_type = "GROUP"
          resource_name = perm.group
          pattern_type  = perm.pattern_type
          operation     = op
          principal     = local.principal
          permission    = local.permission
          host          = local.host
        }
      ]
    ]) : entry.key => entry
  }

  # Normalize and flatten transactional ID permissions
  normalized_transactional_id_acls = {
    for entry in flatten([
      for perm in var.transactional_id_permissions : [
        for op in perm.operations : {
          key           = "TRANSACTIONAL_ID:${perm.transactional_id}:${perm.pattern_type}:${op}"
          resource_type = "TRANSACTIONAL_ID"
          resource_name = perm.transactional_id
          pattern_type  = perm.pattern_type
          operation     = op
          principal     = local.principal
          permission    = local.permission
          host          = local.host
        }
      ]
    ]) : entry.key => entry
  }

  # Flatten cluster permissions with fixed resource_name and pattern_type
  normalized_cluster_acls = {
    for op in var.cluster_permissions.operations : "CLUSTER:kafka-cluster:LITERAL:${op}" => {
      resource_type = "CLUSTER"
      resource_name = "kafka-cluster"
      pattern_type  = "LITERAL"
      operation     = op
      principal     = local.principal
      permission    = local.permission
      host          = local.host
    }
  }

  # Combine all ACL types
  all_acls = merge(local.normalized_topic_acls, local.normalized_group_acls, local.normalized_transactional_id_acls, local.normalized_cluster_acls)
}

resource "confluent_service_account" "this" {
  display_name = var.service_account_display_name
  description  = "Service account for ${var.name} workload in ${var.environment_name}."

  lifecycle {
    precondition {
      condition     = length(var.schema_subject_permissions) == 0 || var.schema_registry != null
      error_message = "schema_subject_permissions requires schema_registry to be non-null."
    }
  }
}

resource "confluent_api_key" "kafka" {
  display_name = "${var.name}-kafka-api-key"
  description  = "Kafka API key for ${var.name} workload in ${var.environment_name}."

  owner {
    id          = confluent_service_account.this.id
    api_version = confluent_service_account.this.api_version
    kind        = confluent_service_account.this.kind
  }

  managed_resource {
    id          = var.kafka_cluster_id
    api_version = local.kafka_cluster_api_version
    kind        = local.kafka_cluster_kind

    environment {
      id = var.environment_id
    }
  }
}

resource "confluent_api_key" "schema_registry" {
  for_each = local.sr_for_each

  display_name = "${var.name}-schema-registry-api-key"
  description  = "Schema Registry API key for ${var.name} workload in ${var.environment_name}."

  owner {
    id          = confluent_service_account.this.id
    api_version = confluent_service_account.this.api_version
    kind        = confluent_service_account.this.kind
  }

  managed_resource {
    id          = each.value.cluster_id
    api_version = local.sr_cluster_api_version
    kind        = local.sr_cluster_kind

    environment {
      id = var.environment_id
    }
  }
}

resource "confluent_kafka_acl" "acl" {
  for_each = local.all_acls

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  resource_type = each.value.resource_type
  resource_name = each.value.resource_name
  pattern_type  = each.value.pattern_type
  principal     = each.value.principal
  host          = each.value.host
  operation     = each.value.operation
  permission    = each.value.permission

  rest_endpoint = var.kafka_rest_endpoint
  credentials {
    key    = var.kafka_admin_credentials.api_key
    secret = var.kafka_admin_credentials.api_secret
  }
}

resource "confluent_role_binding" "schema_subject" {
  for_each = local.sr_configured ? {
    for index, perm in var.schema_subject_permissions : "SR_SUBJECT:${perm.subject}:${perm.role}" => {
      subject = perm.subject
      role    = perm.role
    }
  } : {}

  principal   = local.principal
  role_name   = each.value.role
  crn_pattern = "${nonsensitive(var.schema_registry.resource_name)}/subject=${each.value.subject}"
}
