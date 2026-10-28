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
# AWS EKS Aurora — Generic Example
#
# Aurora PostgreSQL cluster with no workload-specific tuning.
# Uses Aurora defaults for all parameters. Individual overrides shown.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

module "generic_db" {
  source = "../../modules/aws-eks-aurora-cluster"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "appdata"
  workload_preset            = "generic"
  database_name              = "appdata"
  vpc_id                     = "vpc-0123456789abcdef0"
  subnet_ids                 = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
  allowed_security_group_ids = ["sg-workload"]

  # Individual override example — set random_page_cost even though generic preset omits it
  random_page_cost = "1.1"
}

output "cluster_endpoint" {
  value = module.generic_db.cluster_endpoint
}

output "master_secret_arn" {
  value = module.generic_db.master_secret_arn
}
