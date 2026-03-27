variable "name" {
  type        = string
  description = "Workload name, used in resource naming."
}

variable "environment_id" {
  type        = string
  description = "Confluent Cloud environment ID (e.g. env-abc123)."

  validation {
    condition     = can(regex("^env-", var.environment_id))
    error_message = "environment_id must start with 'env-' (e.g., env-abc123)."
  }
}

variable "environment_name" {
  type        = string
  description = "Logical name (e.g. staging) for display names."
}

variable "kafka_cluster_id" {
  type        = string
  description = "Kafka cluster ID (e.g. lkc-abc123)."

  validation {
    condition     = can(regex("^lkc-", var.kafka_cluster_id))
    error_message = "kafka_cluster_id must start with 'lkc-' (e.g., lkc-abc123)."
  }
}

variable "kafka_rest_endpoint" {
  type        = string
  description = "Kafka REST endpoint URL for ACL management."

  validation {
    condition     = can(regex("^https://", var.kafka_rest_endpoint))
    error_message = "kafka_rest_endpoint must be a valid HTTPS URL."
  }
}

variable "kafka_admin_credentials" {
  type = object({
    api_key    = string
    api_secret = string
  })
  description = "Admin Kafka API key with ACL management permission."
  sensitive   = true

  validation {
    condition     = var.kafka_admin_credentials.api_key != "" && var.kafka_admin_credentials.api_secret != ""
    error_message = "Both api_key and api_secret must be non-empty."
  }
}

variable "service_account_display_name" {
  type        = string
  description = "Display name for the service account."

  validation {
    condition     = trimspace(var.service_account_display_name) != ""
    error_message = "service_account_display_name must be non-empty."
  }
}

variable "topic_permissions" {
  type = list(object({
    topic        = string
    pattern_type = string
    operations   = set(string)
  }))
  description = "Topic-level Kafka ACL permissions."
  default     = []

  validation {
    condition = alltrue([
      for p in var.topic_permissions : contains(["LITERAL", "PREFIXED"], p.pattern_type)
    ])
    error_message = "topic_permissions pattern_type must be either 'LITERAL' or 'PREFIXED'."
  }

  validation {
    condition = alltrue([
      for p in var.topic_permissions : alltrue([
        for op in p.operations : contains([
          "READ", "WRITE", "CREATE", "DELETE", "ALTER", "DESCRIBE", "DESCRIBE_CONFIGS", "ALTER_CONFIGS"
        ], op)
      ])
    ])
    error_message = "topic_permissions operations must be subset of: READ, WRITE, CREATE, DELETE, ALTER, DESCRIBE, DESCRIBE_CONFIGS, ALTER_CONFIGS."
  }

  validation {
    condition = alltrue([
      for p in var.topic_permissions : length(p.operations) > 0
    ])
    error_message = "Each topic_permissions entry must have at least one operation."
  }
}

variable "group_permissions" {
  type = list(object({
    group        = string
    pattern_type = string
    operations   = set(string)
  }))
  description = "Consumer group-level Kafka ACL permissions."
  default     = []

  validation {
    condition = alltrue([
      for p in var.group_permissions : contains(["LITERAL", "PREFIXED"], p.pattern_type)
    ])
    error_message = "group_permissions pattern_type must be either 'LITERAL' or 'PREFIXED'."
  }

  validation {
    condition = alltrue([
      for p in var.group_permissions : alltrue([
        for op in p.operations : contains(["READ", "DESCRIBE", "DELETE"], op)
      ])
    ])
    error_message = "group_permissions operations must be subset of: READ, DESCRIBE, DELETE."
  }

  validation {
    condition = alltrue([
      for p in var.group_permissions : length(p.operations) > 0
    ])
    error_message = "Each group_permissions entry must have at least one operation."
  }
}

variable "cluster_permissions" {
  type = object({
    operations = set(string)
  })
  description = "Cluster-level Kafka ACL permissions (e.g., IDEMPOTENT_WRITE)."
  default     = { operations = [] }

  validation {
    condition = alltrue([
      for op in var.cluster_permissions.operations : contains([
        "IDEMPOTENT_WRITE", "DESCRIBE", "ALTER", "ALTER_CONFIGS", "DESCRIBE_CONFIGS", "CLUSTER_ACTION", "CREATE"
      ], op)
    ])
    error_message = "cluster_permissions operations must be subset of: IDEMPOTENT_WRITE, DESCRIBE, ALTER, ALTER_CONFIGS, DESCRIBE_CONFIGS, CLUSTER_ACTION, CREATE."
  }
}

variable "transactional_id_permissions" {
  type = list(object({
    transactional_id = string
    pattern_type     = string
    operations       = set(string)
  }))
  description = "Transactional ID Kafka ACL permissions for transactional/exactly-once-style producers. Cluster IDEMPOTENT_WRITE remains separate in cluster_permissions."
  default     = []

  validation {
    condition = alltrue([
      for p in var.transactional_id_permissions : contains(["LITERAL", "PREFIXED"], p.pattern_type)
    ])
    error_message = "transactional_id_permissions pattern_type must be either 'LITERAL' or 'PREFIXED'."
  }

  validation {
    condition = alltrue([
      for p in var.transactional_id_permissions : alltrue([
        for op in p.operations : contains(["DESCRIBE", "WRITE"], op)
      ])
    ])
    error_message = "transactional_id_permissions operations must be subset of: DESCRIBE, WRITE."
  }

  validation {
    condition = alltrue([
      for p in var.transactional_id_permissions : length(p.operations) > 0
    ])
    error_message = "Each transactional_id_permissions entry must have at least one operation."
  }
}

variable "schema_registry" {
  type = object({
    cluster_id    = string
    resource_name = string
  })
  description = "Schema Registry cluster configuration. When null, no SR resources are created."
  default     = null

  validation {
    condition     = var.schema_registry == null || can(regex("^lsrc-", var.schema_registry.cluster_id))
    error_message = "schema_registry.cluster_id must start with 'lsrc-' (e.g., lsrc-abc123) or be null."
  }

  validation {
    condition     = var.schema_registry == null || can(regex("^crn://confluent.cloud/", var.schema_registry.resource_name))
    error_message = "schema_registry.resource_name must be a valid CRN starting with 'crn://confluent.cloud/' or be null."
  }
}

variable "schema_subject_permissions" {
  type = list(object({
    subject = string
    role    = string
  }))
  description = "Schema Registry subject-level RBAC permissions. Requires schema_registry to be non-null."
  default     = []

  validation {
    condition = alltrue([
      for p in var.schema_subject_permissions : contains([
        "DeveloperRead", "DeveloperWrite", "ResourceOwner"
      ], p.role)
    ])
    error_message = "schema_subject_permissions role must be one of: DeveloperRead, DeveloperWrite, ResourceOwner."
  }

  validation {
    condition = alltrue([
      for p in var.schema_subject_permissions : trimspace(p.subject) != ""
    ])
    error_message = "Each schema_subject_permissions entry must have a non-empty subject."
  }

}
