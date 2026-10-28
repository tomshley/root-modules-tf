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

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

module "network" {
  source = "../../modules/gcp-network"

  project_id          = var.project_id
  project_name_prefix = "example"
  region              = var.region
}

module "database" {
  source = "../../modules/gcp-cloudsql-postgres"

  project_id                     = var.project_id
  project_name_prefix            = "example"
  workload_name                  = "application"
  region                         = var.region
  private_network_id             = module.network.network_id
  private_services_connection_id = module.network.private_services_connection_id
  database_name                  = "application"
}

check "writer_only_connection_contract" {
  assert {
    condition     = module.database.reader_instance_count == 0 && module.database.reader_endpoint == module.database.cluster_endpoint && module.database.port == 5432
    error_message = "A writer-only Cloud SQL deployment must still expose a PostgreSQL reader endpoint that resolves to the primary endpoint."
  }
}

output "connection" {
  value = {
    host          = module.database.cluster_endpoint
    reader_host   = module.database.reader_endpoint
    port          = module.database.port
    database_name = module.database.database_name
  }
}
