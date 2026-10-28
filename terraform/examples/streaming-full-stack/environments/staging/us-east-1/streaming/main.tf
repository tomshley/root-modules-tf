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
  required_version = ">= 1.9"

  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  # Provider configuration is managed by the workload-access module
  # No global provider configuration needed at this level
}

module "streaming" {
  source = "../../../../stacks/streaming"

  project           = var.project
  environment       = var.environment
  aws_region        = var.aws_region
  streaming_profile = var.streaming_profile
  tags              = var.tags

  # Config from committed terraform.tfvars
  confluent_config = var.confluent_config
  workloads        = var.workloads

  # Secrets from TF_VAR_* env vars (.env secure file)
  kafka_admin_api_key    = var.kafka_admin_api_key
  kafka_admin_api_secret = var.kafka_admin_api_secret
}
