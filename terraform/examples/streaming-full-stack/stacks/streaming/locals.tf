locals {
  project_name_prefix = "${var.project}-${var.environment}-${var.aws_region}"

  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project
    Region      = var.aws_region
  })

  # Map streaming_profile to directory name
  profile_short = var.streaming_profile == "commercial_managed" ? "commercial" : "gov"

  # Null-safe Confluent field access — nonsensitive() strips inherited sensitivity
  # from the sensitive var.confluent parent so these can be used in for_each.
  confluent_configured = nonsensitive(var.confluent != null)
  sr_configured        = nonsensitive(local.confluent_configured && try(var.confluent.schema_registry, null) != null)
  active_workloads     = local.confluent_configured ? var.workloads : {}

  # Split schema_registry: module gets only {cluster_id, resource_name};
  # url is a separate passthrough for bundle rendering.
  # The workload-access module's schema_registry type does NOT accept url.
  # Both the condition and the value must be non-sensitive for module for_each.
  schema_registry_for_module = local.sr_configured ? nonsensitive({
    cluster_id    = var.confluent.schema_registry.cluster_id
    resource_name = var.confluent.schema_registry.resource_name
  }) : null

  # Runtime connection fields — passthrough for outputs/bundle
  kafka_bootstrap_servers = local.confluent_configured ? var.confluent.kafka_bootstrap_servers : null
  schema_registry_url     = local.confluent_configured ? try(var.confluent.schema_registry.url, null) : null
}
