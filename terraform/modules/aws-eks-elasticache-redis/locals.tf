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

locals {
  resolved_sg_description = var.security_group_description != null ? var.security_group_description : "Redis access for ${var.workload_name} workloads"
  resolved_pg_description = var.parameter_group_description != null ? var.parameter_group_description : "Redis parameter group for ${var.workload_name}"
  resolved_rg_description = var.replication_group_description != null ? var.replication_group_description : "Redis cluster for ${var.workload_name}"

  # num_cache_clusters >= 2 is both necessary and sufficient for Multi-AZ +
  # automatic failover on a cluster-mode-disabled replication group.
  # Deriving these flags removes an entire class of
  # "multi_az_enabled = true but num_cache_clusters = 1" misconfigurations
  # that would otherwise fail at apply with a cryptic AWS error.
  ha_enabled = var.num_cache_clusters >= 2
}
