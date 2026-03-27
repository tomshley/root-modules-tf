# Example: Kafka-only workload with external Schema Registry
# Shows Kafka-only topic access for workloads where Schema Registry is managed externally.
# Schema Registry credentials are provisioned separately or in another workspace.

terraform {
  required_providers {
    confluent = {
      source  = "confluentinc/confluent"
      version = "~> 2.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

module "kafka_only_workload" {
  source = "../../modules/confluent-streaming-workload-access"

  # Basic workload identification
  name                         = "example-processor-service"
  environment_id               = "env-abc123"
  environment_name             = "staging"
  kafka_cluster_id             = "lkc-abc123"
  kafka_rest_endpoint          = "https://pkc-abc123.us-east-1.aws.confluent.cloud"
  service_account_display_name = "Example Processor Service"

  # Admin credentials for ACL management (sourced from variables, not hardcoded)
  kafka_admin_credentials = {
    api_key    = var.admin_kafka_api_key
    api_secret = var.admin_kafka_api_secret
  }

  # Topic permissions: read access to input topics, write to output topics
  topic_permissions = [
    {
      topic        = "example-input-events"
      pattern_type = "LITERAL"
      operations   = ["READ"]
    },
    {
      topic        = "example-output-events"
      pattern_type = "LITERAL"
      operations   = ["WRITE"]
    },
    {
      topic        = "example-dlq"
      pattern_type = "LITERAL"
      operations   = ["WRITE"]
    }
  ]

  # Group permissions: consumer group access
  group_permissions = [
    {
      group        = "example-processor-consumer-group"
      pattern_type = "LITERAL"
      operations   = ["READ"]
    }
  ]

  # Cluster permissions: idempotent write support for producers
  cluster_permissions = {
    operations = ["IDEMPOTENT_WRITE"]
  }

  # Schema Registry: omitted (managed externally)
  schema_registry = null

  # No schema_subject_permissions when schema_registry is null
}

# Variables (in practice, these would be in a .tfvars file or secret manager)
variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API key for provider authentication."
  type        = string
  sensitive   = true
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API secret for provider authentication."
  type        = string
  sensitive   = true
}

variable "admin_kafka_api_key" {
  description = "Admin Kafka API key with ACL management permissions."
  type        = string
  sensitive   = true
}

variable "admin_kafka_api_secret" {
  description = "Admin Kafka API secret with ACL management permissions."
  type        = string
  sensitive   = true
}

# Output the workload credentials for downstream use
output "workload_credentials" {
  description = "Workload service account and Kafka API key credentials."
  value = {
    service_account_id         = module.kafka_only_workload.service_account_id
    kafka_api_key_id           = module.kafka_only_workload.kafka_api_key_id
    kafka_api_secret           = module.kafka_only_workload.kafka_api_secret
    schema_registry_api_key_id = module.kafka_only_workload.schema_registry_api_key_id
    schema_registry_api_secret = module.kafka_only_workload.schema_registry_api_secret
  }
  sensitive = true
}
