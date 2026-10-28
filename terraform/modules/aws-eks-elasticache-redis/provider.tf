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

terraform {
  # Cross-variable references inside validation blocks in variables.tf
  # (replication group identifier length check referencing
  # project_name_prefix + workload_name, IAM policy name length check, and
  # num_cache_clusters consistency checks) require
  # Terraform >= 1.9 / OpenTofu >= 1.8. Older CLIs emit a cryptic
  # "Variables not allowed" parse error rather than an actionable
  # "upgrade your CLI" message.
  #
  # The module also sets `transit_encryption_mode = "required"` on
  # aws_elasticache_replication_group, which requires aws provider 5.22+.
  # The `~> 5.0` constraint below is intentionally permissive to stay
  # consistent with the rest of the repo; operators should lock to
  # 5.22+ in their consumer stacks' .terraform.lock.hcl.
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
