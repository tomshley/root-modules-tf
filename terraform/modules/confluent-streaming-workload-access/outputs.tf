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
