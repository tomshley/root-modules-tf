locals {
  # Build set of "service:role" keys that are included by the base overlay
  deployment_include_keys = toset(flatten([
    for inc in var.base_overlay.include : [
      for r in inc.roles : "${inc.service}:${r}"
    ]
  ]))

  # Filter catalog entries by base overlay include rules
  included_topics = [
    for t in var.catalog_entries : t
    if contains(local.deployment_include_keys, "${t.service}:${t.role}")
  ]

  # Apply base exclusions and region-specific exclusions
  all_exclusions = concat(var.base_overlay.exclude_topics, var.region_exclusions.exclude_topics)

  active_topics = {
    for t in local.included_topics : t.name => t
    if !contains(local.all_exclusions, t.name)
  }
}

resource "confluent_kafka_topic" "managed" {
  for_each = local.active_topics

  kafka_cluster {
    id = var.kafka_cluster_id
  }

  topic_name       = each.value.name
  partitions_count = each.value.partitions
  rest_endpoint    = var.kafka_rest_endpoint

  # Conditionally emit delete.retention.ms / min.compaction.lag.ms so
  # consumers that omit the optional fields land Kafka's defaults
  # (24h / 0ms) without an explicit "" or "0" override surfacing in the
  # broker config. The merge() pattern keeps the always-on
  # cleanup.policy + retention.ms in a single literal block so the
  # required-config shape stays obvious to readers, with the two
  # optional knobs layered as one-key maps that drop to {} when null.
  # tostring() is required because confluent_kafka_topic.config is
  # map(string); omitting it would supply a number where a string is
  # expected, surfacing as a "string required" coercion failure when
  # the merged map(any) result is assigned to the resource's
  # map(string)-typed config attribute.
  config = merge(
    {
      "cleanup.policy" = each.value.cleanup_policy
      "retention.ms"   = tostring(each.value.retention_ms)
    },
    each.value.delete_retention_ms != null ? {
      "delete.retention.ms" = tostring(each.value.delete_retention_ms)
    } : {},
    each.value.min_compaction_lag_ms != null ? {
      "min.compaction.lag.ms" = tostring(each.value.min_compaction_lag_ms)
    } : {},
  )

  credentials {
    key    = var.kafka_admin_credentials.api_key
    secret = var.kafka_admin_credentials.api_secret
  }

  lifecycle {
    prevent_destroy = true
  }
}
