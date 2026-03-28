# Example: streaming-topics-overlay
#
# Demonstrates the confluent-streaming-topics module with:
#   - 2 services (ingest, transform), each with 2 roles (core, dlq)
#   - One topic explicitly excluded via base_overlay.exclude_topics
#   - region_exclusions passed as empty (no region-specific filtering)
#   - Inline catalog_entries and base_overlay showing the consumer-side parsing pattern
#
# In a real consumer (e.g. ami-infrastructure), catalog_entries and base_overlay
# are parsed from YAML files via fileset() + yamldecode(). This example uses
# inline values to show the shape the module expects.

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
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# ---------------------------------------------------------------------------
# Inline catalog entries (consumer would parse these from YAML catalogs)
# ---------------------------------------------------------------------------
locals {
  catalog_entries = [
    # ingest/core.yaml
    {
      name           = "raw-events"
      partitions     = 6
      retention_ms   = 604800000
      cleanup_policy = "delete"
      service        = "ingest"
      role           = "core"
    },
    # ingest/dlq.yaml
    {
      name           = "raw-events-dlq"
      partitions     = 1
      retention_ms   = 1209600000
      cleanup_policy = "delete"
      service        = "ingest"
      role           = "dlq"
    },
    # transform/core.yaml
    {
      name           = "enriched-events"
      partitions     = 6
      retention_ms   = 604800000
      cleanup_policy = "delete"
      service        = "transform"
      role           = "core"
    },
    # transform/dlq.yaml
    {
      name           = "enriched-events-dlq"
      partitions     = 1
      retention_ms   = 1209600000
      cleanup_policy = "delete"
      service        = "transform"
      role           = "dlq"
    },
  ]

  # Deployment overlay (consumer would yamldecode from base.yaml)
  # This overlay includes both services with both roles, but explicitly
  # excludes one topic by name.
  base_overlay = {
    include = [
      { service = "ingest", roles = ["core", "dlq"] },
      { service = "transform", roles = ["core", "dlq"] },
    ]
    exclude_topics = ["enriched-events-dlq"]
  }
}

# ---------------------------------------------------------------------------
# Module call — guarded by confluent_configured in a real consumer
# ---------------------------------------------------------------------------
module "streaming_topics" {
  source = "../../terraform/modules/confluent-streaming-topics"

  catalog_entries         = local.catalog_entries
  base_overlay            = local.base_overlay
  region_exclusions       = { exclude_topics = [] }
  kafka_cluster_id        = var.kafka_cluster_id
  kafka_rest_endpoint     = var.kafka_rest_endpoint
  kafka_admin_credentials = var.kafka_admin_credentials
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "confluent_cloud_api_key" {
  type      = string
  sensitive = true
}

variable "confluent_cloud_api_secret" {
  type      = string
  sensitive = true
}

variable "kafka_cluster_id" {
  type    = string
  default = "lkc-example"
}

variable "kafka_rest_endpoint" {
  type    = string
  default = "https://pkc-example.us-east-1.aws.confluent.cloud:443/kafka/v3"
}

variable "kafka_admin_credentials" {
  type = object({
    api_key    = string
    api_secret = string
  })
  sensitive = true
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "active_topic_summary" {
  description = "Summary of topics created after overlay filtering."
  value       = module.streaming_topics.active_topic_summary
}

output "catalog_summary" {
  description = "Summary of all catalog entries before filtering."
  value       = module.streaming_topics.catalog_summary
}

# Expected result:
# - 4 catalog entries (raw-events, raw-events-dlq, enriched-events, enriched-events-dlq)
# - 3 active topics (enriched-events-dlq excluded by base_overlay.exclude_topics)
# - active: raw-events, raw-events-dlq, enriched-events
