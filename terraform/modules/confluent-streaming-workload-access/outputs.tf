output "service_account_id" {
  value = confluent_service_account.this.id
}

output "kafka_api_key_id" {
  value = confluent_api_key.kafka.id
}

output "kafka_api_secret" {
  value     = confluent_api_key.kafka.secret
  sensitive = true
}

output "schema_registry_api_key_id" {
  value = try(confluent_api_key.schema_registry["default"].id, null)
}

output "schema_registry_api_secret" {
  value     = try(confluent_api_key.schema_registry["default"].secret, null)
  sensitive = true
}
