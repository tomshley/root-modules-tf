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

output "cluster_endpoint" {
  value = google_sql_database_instance.primary.private_ip_address
}

output "reader_endpoint" {
  value = var.reader_instance_count == 0 ? google_sql_database_instance.primary.private_ip_address : google_sql_database_instance.reader[0].private_ip_address
}

output "port" {
  value = var.port
}

output "database_name" {
  value = google_sql_database.default.name
}

output "master_username" {
  value = google_sql_user.master.name
}

output "master_secret_id" {
  value = google_secret_manager_secret.master.id
}

output "connection_name" {
  value = google_sql_database_instance.primary.connection_name
}

output "reader_instance_count" {
  value = var.reader_instance_count
}

output "workload_contract" {
  value       = module.workload_contract.contract
  description = "The normalized PostgreSQL workload contract applied by this adapter."
}
