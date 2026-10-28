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

###############################################################################
# AWS EKS Aurora — CQRS Pair Example
#
# Two Aurora clusters composed: write-optimized event store + read-optimized
# read model. Demonstrates how a single consumer root module uses the same
# generic module twice with different presets.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

# --- Write Side (Event Store) ---

module "journal_db" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "event-journal"
  workload_preset            = "event-store"
  database_name              = "event_journal"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]
}

# --- Read Side (Read Model) ---

module "readmodel_db" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "readmodel"
  workload_preset            = "read-store"
  database_name              = "readmodel"
  reader_instance_count      = 1
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]
}

# --- Outputs ---

output "journal_endpoint" {
  value = module.journal_db.cluster_endpoint
}

output "journal_secret_arn" {
  value = module.journal_db.master_secret_arn
}

output "readmodel_endpoint" {
  value = module.readmodel_db.cluster_endpoint
}

output "readmodel_reader_endpoint" {
  value = module.readmodel_db.reader_endpoint
}

output "readmodel_secret_arn" {
  value = module.readmodel_db.master_secret_arn
}
