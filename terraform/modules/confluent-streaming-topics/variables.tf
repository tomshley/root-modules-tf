variable "catalog_entries" {
  description = <<-EOT
    Pre-parsed topic entries from the consumer's YAML catalogs. Each entry
    must include name, partitions, retention_ms, cleanup_policy, service,
    and role. Additional fields (owner, notes) are passed through but not
    used by this module.

    Optional compaction-tuning fields:
      - delete_retention_ms: emitted as Kafka `delete.retention.ms` when
        non-null. Controls the tombstone retention grace window for
        compacted+delete topics. Kafka default is 86400000 (24h);
        compacted-with-delete consumers (CDC sinks, change-log readers)
        often want 7 days (604800000) so a paused consumer can recover
        without missing tombstones.
      - min_compaction_lag_ms: emitted as Kafka `min.compaction.lag.ms`
        when non-null. Minimum age a record must reach before it is
        eligible for compaction; default 0 (eligible immediately).

    Both fields default to null and are omitted from the topic config
    when null, so existing consumers that don't set them continue to
    receive Kafka's defaults — fully additive on existing catalogs.
  EOT
  type = list(object({
    name                  = string
    partitions            = number
    retention_ms          = number
    cleanup_policy        = string
    service               = string
    role                  = string
    delete_retention_ms   = optional(number)
    min_compaction_lag_ms = optional(number)
  }))

  validation {
    condition     = length(var.catalog_entries) == length(distinct([for t in var.catalog_entries : t.name]))
    error_message = "catalog_entries must not contain duplicate topic names."
  }

  # cleanup_policy must be one of Kafka's four canonical comma-list
  # forms. Kafka treats cleanup.policy as an order-agnostic list of
  # policies, so both "compact,delete" and "delete,compact" are valid
  # at the broker — the Apache Kafka and Confluent docs explicitly use
  # "delete,compact" as the canonical example, so an operator copying
  # from upstream docs would otherwise hit an unexpected plan-time
  # rejection. Without this gate a typo ("compcat", "compact, delete"
  # with a stray space, "compaction") falls through plan and surfaces
  # as an opaque Confluent provider error at apply time — and would
  # also slip past the downstream substring-based "compact" gates
  # below since strcontains("compaction", "compact") is true. Enumerate
  # explicitly so the failure shape is closest-to-operator and the
  # substring gates below are constrained to a known-safe value space.
  validation {
    condition = alltrue([
      for t in var.catalog_entries :
      contains(["delete", "compact", "compact,delete", "delete,compact"], t.cleanup_policy)
    ])
    error_message = "cleanup_policy must be one of: 'delete', 'compact', 'compact,delete', 'delete,compact' (no whitespace; both orderings of the dual form are accepted, matching Kafka's order-agnostic list semantics)."
  }

  # delete_retention_ms / min_compaction_lag_ms are operationally
  # meaningful only on topics whose cleanup_policy includes "compact".
  # A pure cleanup_policy = "delete" topic with delete_retention_ms set
  # is almost certainly a misconfiguration (the field has no effect on
  # non-compacted topics — Kafka silently accepts and ignores it). Catch
  # at plan time so reviewers see the intent mismatch instead of the
  # field landing inert on the broker. min_compaction_lag_ms gets the
  # same treatment. strcontains is preferred over can(regex(...)) here
  # for intent clarity (Terraform 1.5+ / OpenTofu 1.6+; the module
  # already requires >= 1.9 in provider.tf).
  validation {
    condition = alltrue([
      for t in var.catalog_entries :
      t.delete_retention_ms == null || strcontains(t.cleanup_policy, "compact")
    ])
    error_message = "delete_retention_ms is only meaningful when cleanup_policy includes 'compact' (e.g. 'compact' or 'compact,delete'). Remove it from delete-only topics or change cleanup_policy."
  }

  validation {
    condition = alltrue([
      for t in var.catalog_entries :
      t.min_compaction_lag_ms == null || strcontains(t.cleanup_policy, "compact")
    ])
    error_message = "min_compaction_lag_ms is only meaningful when cleanup_policy includes 'compact'. Remove it from delete-only topics or change cleanup_policy."
  }

  # Kafka rejects negative values for both fields (Range.atLeast(0) on
  # the broker config validators). Without these gates a negative value
  # surfaces as a cryptic Confluent provider error minutes into apply.
  validation {
    condition = alltrue([
      for t in var.catalog_entries :
      t.delete_retention_ms == null || t.delete_retention_ms >= 0
    ])
    error_message = "delete_retention_ms must be >= 0 (Kafka rejects negative values for delete.retention.ms)."
  }

  validation {
    condition = alltrue([
      for t in var.catalog_entries :
      t.min_compaction_lag_ms == null || t.min_compaction_lag_ms >= 0
    ])
    error_message = "min_compaction_lag_ms must be >= 0 (Kafka rejects negative values for min.compaction.lag.ms)."
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
