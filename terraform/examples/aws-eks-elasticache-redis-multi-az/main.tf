###############################################################################
# AWS EKS ElastiCache Redis — Multi-AZ Example
#
# Highly-available Redis replication group with Multi-AZ + automatic
# failover (derived from num_cache_clusters >= 2), daily snapshots, SNS
# event notifications, and optional CloudWatch slow-log delivery.
# Composed with aws-eks-irsa to show the runtime IRSA binding every
# consumer workload needs.
#
# Replace placeholder values before applying.
###############################################################################

variable "project_name_prefix" {
  type    = string
  default = "example-eks"
}

variable "oidc_provider_arn" {
  type        = string
  description = "OIDC provider ARN from the EKS cluster module. Required — no default to prevent accidental apply with fictitious values."
}

variable "oidc_provider_url" {
  type        = string
  description = "OIDC provider URL (without https://) from the EKS cluster module. Required — no default to prevent accidental apply with fictitious values."
}

# Out-of-band CloudWatch log group — this module does not create it.
# Replace the ARN below with your real group's ARN before applying.
variable "slow_log_destination_arn" {
  type        = string
  default     = null
  description = "CloudWatch log group ARN for Redis slow-log delivery. null disables slow-log delivery."
}

variable "events_topic_arn" {
  type        = string
  default     = null
  description = "SNS topic ARN for ElastiCache event notifications (failover, backup completion). null disables notifications."
}

module "redis" {
  source = "../../modules/aws-eks-elasticache-redis"

  project_name_prefix        = var.project_name_prefix
  workload_name              = "sessions"
  vpc_id                     = "vpc-REPLACE_WITH_YOUR_VPC_ID"
  subnet_ids                 = ["subnet-REPLACE_1", "subnet-REPLACE_2", "subnet-REPLACE_3"]
  allowed_security_group_ids = ["sg-REPLACE_WITH_WORKLOAD_SG"]

  # Two nodes triggers Multi-AZ + automatic failover via the module's
  # HA derivation; no extra flags needed.
  num_cache_clusters = 2
  node_type          = "cache.t4g.small"

  # Session stores and OTP caches are NOT pure cache — 7-day snapshot
  # retention lets operators rebuild from the most recent backup on
  # Scenario C replication-group rebuild. Pair with final_snapshot_identifier
  # if you also want a destroy-time snapshot.
  snapshot_retention_limit = 7
  snapshot_window          = "03:00-04:00"

  notification_topic_arn = var.events_topic_arn

  # Optional slow-log delivery. Omit the configuration (leave list empty)
  # if you have not yet provisioned a CloudWatch log group.
  log_delivery_configurations = var.slow_log_destination_arn == null ? [] : [
    {
      destination      = var.slow_log_destination_arn
      destination_type = "cloudwatch-logs"
      log_format       = "json"
      log_type         = "slow-log"
    },
  ]
}

# --- Consumer IRSA binding (one role per workload ServiceAccount) ---
#
# Mirrors the pattern in examples/aws-eks-aurora-multi-tenant: iterate a
# keys-known-at-plan-time input (var.workloads) and look up the unknown
# policy ARN on the module output by key. Iterating
# module.redis.app_read_policy_arn directly would be fine here because
# it is a single scalar — the variable-driven shape is used only to
# demonstrate how to attach multiple workloads to the same cluster.

variable "workloads" {
  type = map(object({
    namespace       = string
    service_account = string
  }))
  default = {
    app = {
      namespace       = "default"
      service_account = "sessions-app"
    }
  }
  description = "Consumer workloads that need to read the Redis AUTH secret. Each entry maps to one IRSA role."
}

module "workload_irsa" {
  source   = "../../modules/aws-eks-irsa"
  for_each = var.workloads

  project_name_prefix  = var.project_name_prefix
  role_name_suffix     = "${each.key}-redis"
  oidc_provider_arn    = var.oidc_provider_arn
  oidc_provider_url    = var.oidc_provider_url
  namespace            = each.value.namespace
  service_account_name = each.value.service_account
  policy_arns          = [module.redis.app_read_policy_arn]
}

# --- Outputs ---

output "primary_endpoint" {
  value = module.redis.primary_endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint for load-balanced read traffic across the replica."
  value       = module.redis.reader_endpoint
}

output "auth_token_secret_arn" {
  description = "ARN of the AUTH token Secrets Manager secret. Consumers read via the IRSA roles below, not directly."
  value       = module.redis.auth_token_secret_arn
}

output "workload_role_arns" {
  description = "Per-workload runtime IRSA role ARNs with read access to the AUTH secret."
  value       = { for k, m in module.workload_irsa : k => m.role_arn }
}
