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

  # Config is non-sensitive — no nonsensitive() gymnastics needed.
  confluent_configured = var.confluent_config != null
  sr_configured        = local.confluent_configured && var.confluent_config.schema_registry != null
  active_workloads     = local.confluent_configured ? var.workloads : {}

  # Reconstruct credential object from flat TF_VAR_* inputs for module calls.
  kafka_admin_credentials = (var.kafka_admin_api_key != null && var.kafka_admin_api_secret != null) ? {
    api_key    = var.kafka_admin_api_key
    api_secret = var.kafka_admin_api_secret
  } : null
}

check "credentials_accompany_config" {
  assert {
    condition     = var.confluent_config == null || (var.kafka_admin_api_key != null && var.kafka_admin_api_secret != null)
    error_message = "kafka_admin_api_key and kafka_admin_api_secret are required when confluent_config is set. Inject via TF_VAR_kafka_admin_api_key and TF_VAR_kafka_admin_api_secret in your .env secure file."
  }
}

locals {

  # Split schema_registry: module gets only {cluster_id, resource_name};
  # url is a separate passthrough for bundle rendering.
  # The workload-access module's schema_registry type does NOT accept url.
  schema_registry_for_module = local.sr_configured ? {
    cluster_id    = var.confluent_config.schema_registry.cluster_id
    resource_name = var.confluent_config.schema_registry.resource_name
  } : null

  # Runtime connection fields — passthrough for outputs/bundle
  kafka_bootstrap_servers = local.confluent_configured ? var.confluent_config.kafka_bootstrap_servers : null
  schema_registry_url     = local.confluent_configured ? try(var.confluent_config.schema_registry.url, null) : null
}
