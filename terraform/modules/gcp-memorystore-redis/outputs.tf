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

output "primary_endpoint" {
  value = google_redis_instance.this.host
}

output "reader_endpoint" {
  value = google_redis_instance.this.host
}

output "port" {
  value = google_redis_instance.this.port
}

output "auth_token_secret_id" {
  value = google_secret_manager_secret.auth.id
}

output "app_read_policy_arn" {
  value = "roles/secretmanager.secretAccessor"
}

output "instance_id" {
  value = google_redis_instance.this.id
}

output "redis_contract" {
  description = "The normalized Redis contract when the additive contract input is used; null preserves the legacy caller path."
  value       = var.redis_contract == null ? null : module.redis_contract[0].contract
}
