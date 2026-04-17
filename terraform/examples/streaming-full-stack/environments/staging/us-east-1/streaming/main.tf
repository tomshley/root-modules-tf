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
  confluent         = var.confluent
  workloads         = var.workloads
  tags              = var.tags
}
