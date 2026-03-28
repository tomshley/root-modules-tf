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

  config = {
    "cleanup.policy" = each.value.cleanup_policy
    "retention.ms"   = tostring(each.value.retention_ms)
  }

  credentials {
    key    = var.kafka_admin_credentials.api_key
    secret = var.kafka_admin_credentials.api_secret
  }

  lifecycle {
    prevent_destroy = true
  }
}
