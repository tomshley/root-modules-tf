# Example: Commercial streaming workload with Schema Registry access
# Shows Kafka read/write workload with consumer group access,
# cluster_permissions for idempotent producers, and Schema Registry enabled.

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

module "example_workload" {
  source = "../../modules/confluent-streaming-workload-access"

  # Basic workload identification
  name                         = "example-ingest-service"
  environment_id               = "env-abc123"
  environment_name             = "staging"
  kafka_cluster_id             = "lkc-abc123"
  kafka_rest_endpoint          = "https://pkc-abc123.us-east-1.aws.confluent.cloud"
  service_account_display_name = "Example Ingest Service"

  # Admin credentials for ACL management (sourced from variables, not hardcoded)
  kafka_admin_credentials = {
    api_key    = var.admin_kafka_api_key
    api_secret = var.admin_kafka_api_secret
  }

  # Topic permissions: read/write access to input and output topics
  topic_permissions = [
    {
      topic        = "example-input-events"
      pattern_type = "LITERAL"
      operations   = ["READ", "WRITE"]
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
      group        = "example-ingest-consumer-group"
      pattern_type = "LITERAL"
      operations   = ["READ"]
    }
  ]

  transactional_id_permissions = [
    {
      transactional_id = "example-ingest-"
      pattern_type     = "PREFIXED"
      operations       = ["DESCRIBE", "WRITE"]
    }
  ]

  # Cluster permissions: idempotent write support for producers
  cluster_permissions = {
    operations = ["IDEMPOTENT_WRITE"]
  }

  # Schema Registry: enabled with DeveloperRead on all subjects
  schema_registry = {
    cluster_id    = "lsrc-abc123"
    resource_name = "crn://confluent.cloud/organization=abc123/environment=env-abc123/schema-registry=lsrc-abc123"
  }

  schema_subject_permissions = [
    {
      subject = "*"
      role    = "DeveloperRead"
    },
    {
      subject = "example-input-events-value"
      role    = "DeveloperWrite"
    },
    {
      subject = "example-output-events-value"
      role    = "DeveloperWrite"
    }
  ]
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
  description = "Workload service account and API key credentials."
  value = {
    service_account_id         = module.example_workload.service_account_id
    kafka_api_key_id           = module.example_workload.kafka_api_key_id
    kafka_api_secret           = module.example_workload.kafka_api_secret
    schema_registry_api_key_id = module.example_workload.schema_registry_api_key_id
    schema_registry_api_secret = module.example_workload.schema_registry_api_secret
  }
  sensitive = true
}
