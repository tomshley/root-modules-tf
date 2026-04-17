variable "project" {
  type    = string
  default = "myproject"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "project must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  type    = string
  default = "staging"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier such as us-east-1."
  }
}

variable "streaming_profile" {
  type    = string
  default = "commercial_managed"
}

variable "confluent_config" {
  type = object({
    environment_id          = string # e.g. "env-abc123"
    environment_name        = string # e.g. "staging"
    kafka_cluster_id        = string # e.g. "lkc-abc123"
    kafka_rest_endpoint     = string # e.g. "https://pkc-abc123.us-east-1.aws.confluent.cloud:443"
    kafka_bootstrap_servers = string # e.g. "pkc-abc123.us-east-1.aws.confluent.cloud:9092"
    schema_registry = optional(object({
      cluster_id    = string # e.g. "lsrc-abc123"
      resource_name = string # CRN string
      url           = string # e.g. "https://psrc-abc123.us-east-1.aws.confluent.cloud"
    }))
  })
  default     = null
  description = "Confluent Cloud environment configuration. When null, no Confluent resources are created."
}

variable "kafka_admin_api_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Kafka cluster admin API key. Injected via TF_VAR_kafka_admin_api_key from .env secure file."
}

variable "kafka_admin_api_secret" {
  type        = string
  default     = null
  sensitive   = true
  description = "Kafka cluster admin API secret. Injected via TF_VAR_kafka_admin_api_secret from .env secure file."
}

variable "workloads" {
  type = map(object({
    service_account_display_name = string
    topic_permissions = optional(list(object({
      topic        = string
      pattern_type = string      # LITERAL | PREFIXED
      operations   = set(string) # READ, WRITE, CREATE, DESCRIBE, etc.
    })), [])
    group_permissions = optional(list(object({
      group        = string
      pattern_type = string
      operations   = set(string)
    })), [])
    transactional_id_permissions = optional(list(object({
      transactional_id = string
      pattern_type     = string
      operations       = set(string)
    })), [])
    cluster_permissions = optional(object({
      operations = set(string)
    }), { operations = [] })
    schema_subject_permissions = optional(list(object({
      subject = string
      role    = string
    })), [])
  }))
  default = {}
}


variable "tags" {
  type    = map(string)
  default = {}
}
