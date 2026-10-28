# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

output "streaming_profile" {
  value = module.streaming.streaming_profile
}

output "confluent_configured" {
  value = module.streaming.confluent_configured
}

output "topic_catalog_summary" {
  value = module.streaming.topic_catalog_summary
}

output "active_topic_summary" {
  value = module.streaming.active_topic_summary
}

output "kafka_bootstrap_servers" {
  value     = module.streaming.kafka_bootstrap_servers
  sensitive = true
}

output "schema_registry_url" {
  value     = module.streaming.schema_registry_url
  sensitive = true
}

output "workload_service_account_ids" {
  value = module.streaming.workload_service_account_ids
}

output "workload_kafka_api_key_ids" {
  value = module.streaming.workload_kafka_api_key_ids
}

output "workload_kafka_api_secrets" {
  value     = module.streaming.workload_kafka_api_secrets
  sensitive = true
}

output "workload_schema_registry_api_key_ids" {
  value = module.streaming.workload_schema_registry_api_key_ids
}

output "workload_schema_registry_api_secrets" {
  value     = module.streaming.workload_schema_registry_api_secrets
  sensitive = true
}
