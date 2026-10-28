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
# AWS EKS Aurora — Read Store Example
#
# Read-optimized Aurora PostgreSQL cluster using the read-store preset.
# Includes one reader instance for read scaling.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

module "read_store" {
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

output "cluster_endpoint" {
  value = module.read_store.cluster_endpoint
}

output "reader_endpoint" {
  value = module.read_store.reader_endpoint
}

output "master_secret_arn" {
  value = module.read_store.master_secret_arn
}
