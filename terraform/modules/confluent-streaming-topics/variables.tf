variable "catalog_entries" {
  description = "Pre-parsed topic entries from the consumer's YAML catalogs. Each entry must include name, partitions, retention_ms, cleanup_policy, service, and role. Additional fields (owner, notes) are passed through but not used by this module."
  type = list(object({
    name           = string
    partitions     = number
    retention_ms   = number
    cleanup_policy = string
    service        = string
    role           = string
  }))

  validation {
    condition     = length(var.catalog_entries) == length(distinct([for t in var.catalog_entries : t.name]))
    error_message = "catalog_entries must not contain duplicate topic names."
  }
}

variable "base_overlay" {
  description = "Deployment overlay controlling which service/role combinations are active. include is a list of {service, roles} objects. exclude_topics is a list of topic names to skip even if matched by include."
  type = object({
    include = list(object({
      service = string
      roles   = list(string)
    }))
    exclude_topics = list(string)
  })
}

variable "region_exclusions" {
  description = "Optional region-specific exclusions. Topics listed here are removed after base overlay filtering."
  type = object({
    exclude_topics = list(string)
  })
  default = { exclude_topics = [] }
}

variable "kafka_cluster_id" {
  description = "Confluent Kafka cluster ID (e.g. lkc-abc123)."
  type        = string

  validation {
    condition     = can(regex("^lkc-", var.kafka_cluster_id))
    error_message = "kafka_cluster_id must start with 'lkc-'."
  }
}

variable "kafka_rest_endpoint" {
  description = "Confluent Kafka REST endpoint URL."
  type        = string

  validation {
    condition     = can(regex("^https://", var.kafka_rest_endpoint))
    error_message = "kafka_rest_endpoint must start with 'https://'."
  }
}

variable "kafka_admin_credentials" {
  description = "API key and secret for Kafka admin operations."
  type = object({
    api_key    = string
    api_secret = string
  })
  sensitive = true
}
