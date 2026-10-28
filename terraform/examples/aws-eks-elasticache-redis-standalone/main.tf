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
# AWS EKS ElastiCache Redis — Standalone Example
#
# Single-node Redis replication group (no failover, no Multi-AZ) sized for
# development environments, smoke tests, and low-throughput caches.
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

module "redis" {
  source = "../../modules/aws-eks-elasticache-redis"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "sessions"
  vpc_id                     = "vpc-REPLACE_WITH_YOUR_VPC_ID"
  subnet_ids                 = ["subnet-REPLACE_1", "subnet-REPLACE_2", "subnet-REPLACE_3"]
  allowed_security_group_ids = ["sg-REPLACE_WITH_WORKLOAD_SG"]

  # Single-node for dev — no Multi-AZ, no replicas. multi_az_enabled and
  # automatic_failover_enabled are derived from num_cache_clusters and stay
  # off in this configuration.
  num_cache_clusters = 1
  node_type          = "cache.t4g.micro"

  # Staging / dev: frequent tear-down and rebuild. Shortening the recovery
  # window to 0 lets the same workload name be recreated immediately.
  auth_secret_recovery_window_in_days = 0
}

output "primary_endpoint" {
  value = module.redis.primary_endpoint
}

output "auth_token_secret_arn" {
  value = module.redis.auth_token_secret_arn
}

output "app_read_policy_arn" {
  value = module.redis.app_read_policy_arn
}
