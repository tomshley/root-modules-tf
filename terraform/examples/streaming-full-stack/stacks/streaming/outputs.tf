output "streaming_profile" {
  value = var.streaming_profile
}

output "confluent_configured" {
  value = local.confluent_configured
}

output "topic_catalog_summary" {
  description = "Summary of all topics loaded from service catalogs."
  value = {
    by_role = {
      core = length([for t in local.all_topics : t if t.role == "core"])
      flat = length([for t in local.all_topics : t if t.role == "flat"])
      dlq  = length([for t in local.all_topics : t if t.role == "dlq"])
    }
    by_service = {
      for svc in distinct([for t in local.all_topics : t.service]) :
      svc => [for t in local.all_topics : t.name if t.service == svc]
    }
    total = length(local.all_topics)
    names = [for t in local.all_topics : t.name]
  }
}

output "active_topic_summary" {
  description = "Summary of topics actually created in this deployment (filtered by overlay)."
  value = try(module.streaming_topics["default"].active_topic_summary, {
    by_role    = {}
    by_service = {}
    total      = 0
    names      = []
  })
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap servers for client connections. Null when unconfigured."
  value       = local.kafka_bootstrap_servers
  sensitive   = true
}

output "schema_registry_url" {
  description = "Schema Registry URL for client connections. Null when SR is not configured."
  value       = local.schema_registry_url
  sensitive   = true
}

output "workload_service_account_ids" {
  description = "Map of workload name to Confluent service account ID."
  value       = { for k, v in module.workload_access : k => v.service_account_id }
}

output "workload_kafka_api_key_ids" {
  description = "Map of workload name to Kafka API key ID."
  value       = { for k, v in module.workload_access : k => v.kafka_api_key_id }
}

output "workload_kafka_api_secrets" {
  description = "Map of workload name to Kafka API secret."
  value       = { for k, v in module.workload_access : k => v.kafka_api_secret }
  sensitive   = true
}

output "workload_schema_registry_api_key_ids" {
  description = "Map of workload name to Schema Registry API key ID. Null values when SR disabled."
  value       = { for k, v in module.workload_access : k => v.schema_registry_api_key_id }
}

output "workload_schema_registry_api_secrets" {
  description = "Map of workload name to Schema Registry API secret. Null values when SR disabled."
  value       = { for k, v in module.workload_access : k => v.schema_registry_api_secret }
  sensitive   = true
}
