variable "project_name_prefix" {
  type        = string
  description = "Naming prefix for all resources created by this module."
}

variable "workload_name" {
  type        = string
  description = "Logical workload name used in all resource naming (e.g. portal, session-store)."

  validation {
    condition     = can(regex("^[a-z](-?[a-z0-9])+$", var.workload_name))
    error_message = "workload_name must be lowercase alphanumeric with single hyphens, starting with a letter, minimum 2 characters."
  }

  # AWS ElastiCache replication_group_id is limited to 40 bytes. The base
  # "${project_name_prefix}-${workload_name}" itself is the longest identifier
  # this module generates -- subnet group and parameter group names are
  # capped at 255 bytes by AWS, security group names at 255 bytes, and
  # Secrets Manager secret names at 512 bytes, so none of those are the
  # binding constraint. If the base fits in 40 bytes, every derived
  # identifier fits.
  validation {
    condition     = length("${var.project_name_prefix}-${var.workload_name}") <= 40
    error_message = "Generated ElastiCache replication_group_id (project_name_prefix + workload_name) must not exceed 40 bytes (AWS ElastiCache replication_group_id limit)."
  }

  # Generated IAM policy is "${project_name_prefix}-${workload_name}-redis-read"
  # which AWS caps at 128 bytes. Unlike replication_group_id, the IAM limit
  # can be hit independently with very long prefixes, so validate it
  # explicitly. '-redis-read' (11 bytes) is the only suffix this module
  # produces, so checking it alone is sufficient.
  validation {
    condition     = length("${var.project_name_prefix}-${var.workload_name}-redis-read") <= 128
    error_message = "Generated IAM policy name (project_name_prefix + workload_name + '-redis-read') must not exceed 128 bytes (AWS IAM limit)."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for security group placement."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the ElastiCache subnet group. Provide at least one subnet per AZ you intend to span with num_cache_clusters."

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must contain at least one subnet ID."
  }

  # Multi-AZ + automatic_failover is derived from num_cache_clusters >= 2
  # (see locals.tf::ha_enabled). AWS rejects a Multi-AZ replication group
  # whose subnet group does not span at least two AZs, but the failure
  # surfaces minutes into apply as a cryptic
  # "InsufficientCacheClusterCapacity" / "subnet group must span multiple
  # AZs". Catch the trivial 1-subnet case at plan time.
  #
  # Note: we cannot fully validate "subnets in distinct AZs" without an
  # AWS data lookup, so AWS still owns the same-AZ-twice failure mode at
  # apply time. Cross-variable validation requires Terraform 1.9+ /
  # OpenTofu 1.8+ (already declared in provider.tf).
  validation {
    condition     = var.num_cache_clusters < 2 || length(var.subnet_ids) >= 2
    error_message = "When num_cache_clusters >= 2 (Multi-AZ + automatic failover), subnet_ids must contain at least two subnets. AWS additionally requires they span distinct AZs; that constraint is enforced by ElastiCache at apply time, not by this module (Terraform cannot enumerate subnet AZs without a data lookup)."
  }
}

variable "allowed_security_group_ids" {
  type        = list(string)
  description = "Security group IDs allowed to reach Redis on the configured port. One standalone ingress rule is created per SG (keyed by SG ID, so add/remove is surgical and there are no index-shift races on list changes)."
}

variable "engine_version" {
  type        = string
  default     = "7.1"
  description = <<-EOT
    ElastiCache Redis engine version. Must be Redis 7.x — either a pinned
    minor (`7.0`, `7.1`) or the AWS-native `7.x` alias that tracks the
    latest minor within the 7 major line.

    Redis 6.x is deliberately NOT accepted because this module hardcodes
    `transit_encryption_mode = "required"` on the replication group, and
    that attribute is only supported on Redis 7.0.5+. Accepting a 6.x
    value here would surface as a cryptic AWS InvalidParameterCombination
    error minutes into `apply` rather than a plan-time validation error.
  EOT

  # Bare "7" is rejected: AWS ElastiCache requires either a pinned minor
  # ("7.0", "7.1", ...) or the "7.x" alias. Accepting just "7" at plan time
  # would surface as a cryptic InvalidParameterValue at CreateReplicationGroup,
  # defeating the point of plan-time validation.
  validation {
    condition     = can(regex("^7\\.([0-9]+|x)$", var.engine_version))
    error_message = "engine_version must be Redis 7.x — either a pinned minor (e.g. 7.0, 7.1) or the AWS-native '7.x' alias. Redis 6.x is not supported because transit_encryption_mode = \"required\" requires engine 7.0.5+."
  }
}

variable "parameter_group_family" {
  type        = string
  default     = "redis7"
  description = "Cluster parameter group family. Must be `redis7` — Redis 6.x is not supported by this module (see `engine_version`)."

  validation {
    condition     = var.parameter_group_family == "redis7"
    error_message = "parameter_group_family must be 'redis7'. Redis 6.x (redis6.x) is not supported by this module because transit_encryption_mode = \"required\" requires engine 7.0.5+."
  }
}

variable "node_type" {
  type        = string
  default     = "cache.t4g.micro"
  description = "ElastiCache node instance type. The default is sized for low-throughput workloads; raise for production."
}

variable "num_cache_clusters" {
  type        = number
  default     = 1
  description = <<-EOT
    Number of cache clusters (1 writer + N-1 read replicas) in the
    replication group. Values >= 2 automatically enable Multi-AZ and
    automatic failover; value 1 runs a single-node replication group with
    no failover. Max 6 (AWS limit for cluster-mode-disabled replication
    groups).
  EOT

  validation {
    condition     = var.num_cache_clusters >= 1 && var.num_cache_clusters <= 6
    error_message = "num_cache_clusters must be between 1 and 6."
  }
}

variable "port" {
  type        = number
  default     = 6379
  description = <<-EOT
    Redis TCP port.

    DESTRUCTIVE on change. AWS does NOT support modifying the port of
    an ElastiCache replication group: the AWS Terraform provider marks
    `port` as ForceNew on `aws_elasticache_replication_group` (see
    terraform-provider-aws/internal/service/elasticache/replication_group.go),
    and `aws elasticache modify-replication-group` exposes no `--port`
    parameter. Changing this value therefore destroys the replication
    group AND its dataset, then creates a fresh one on the new port —
    operationally equivalent to Scenario C (replication-group rebuild)
    in the runbook next to `aws_secretsmanager_secret_version.auth` in
    resources.tf. Treat with the same precautions: explicit
    acknowledgement of dataset loss, OR a `final_snapshot_identifier`
    set on the replication group plus a documented restore plan.

    The AUTH token (`random_password.auth_token.result`) survives the
    rebuild because `random_password` is not replaced, and the AUTH
    secret is rewritten automatically by the
    `replace_triggered_by = [aws_elasticache_replication_group.this.arn]`
    on `aws_secretsmanager_secret_version.auth` — no manual
    `put-secret-value` re-sync of `host`/`port` is needed for port
    changes (and any such mutation between plan and apply would race
    the automatic replacement).

    NOTE: this contrasts with the symmetric `var.port` documentation in
    `aws-eks-aurora-cluster`. Aurora does support in-place
    `ModifyDBCluster --port` and so requires a manual secret re-sync;
    ElastiCache does not, and so the port-change handling here is
    structurally different despite the surface-level resemblance.
  EOT

  validation {
    condition     = var.port > 0 && var.port < 65536
    error_message = "port must be a valid TCP port (1-65535)."
  }
}

variable "maintenance_window" {
  type        = string
  default     = "sun:05:00-sun:06:00"
  description = "Weekly maintenance window (UTC). Format: ddd:hh24:mi-ddd:hh24:mi."

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window))
    error_message = "maintenance_window must be in ddd:hh24:mi-ddd:hh24:mi format with lowercase 3-letter weekday and hour 00-23 (e.g. sun:05:00-sun:06:00)."
  }
}

variable "snapshot_retention_limit" {
  type        = number
  default     = 0
  description = "Number of days to retain automatic snapshots. 0 disables automatic backups (acceptable for ephemeral cache); AWS recommends at least 7 for session stores, OTP state, and any Redis use where data loss matters."

  validation {
    condition     = var.snapshot_retention_limit >= 0 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit must be between 0 and 35 days."
  }
}

variable "snapshot_window" {
  type        = string
  default     = "03:00-04:00"
  description = "Daily time range (UTC) during which automatic snapshots are taken. Ignored when snapshot_retention_limit = 0."

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.snapshot_window))
    error_message = "snapshot_window must be in hh24:mi-hh24:mi UTC format with hour 00-23 (e.g. 03:00-04:00)."
  }
}

variable "auto_minor_version_upgrade" {
  type        = bool
  default     = true
  description = "Enable automatic minor version upgrades during maintenance windows."
}

variable "apply_immediately" {
  type        = bool
  default     = false
  description = "Apply parameter group and replication group modifications immediately rather than during the next maintenance window. Leave false in production to respect the maintenance window."
}

variable "kms_key_id" {
  type        = string
  default     = null
  description = "KMS key ID, ARN, or alias for encryption at rest. null (default) uses the AWS-managed ElastiCache key (alias/aws/elasticache). Customer-managed keys are required for CMK-scoped audit and HIPAA-isolated tenants."
}

variable "final_snapshot_identifier" {
  type        = string
  default     = null
  description = <<-EOT
    Identifier for a final snapshot taken on replication group destroy.
    null (default) means NO final snapshot — destroy is immediate and the
    dataset is lost. Set this for any workload where losing cached state
    on Terraform-driven destroy is unacceptable (session stores, OTP
    state, JWT denylists). Ignored on in-place updates; only consulted at
    DeleteReplicationGroup time.
  EOT
}

variable "notification_topic_arn" {
  type        = string
  default     = null
  description = "Optional SNS topic ARN for ElastiCache event notifications (failover, backup completion, node replacement). null disables notifications."
}

variable "security_group_description" {
  type        = string
  default     = null
  description = "Override for the security group description (ForceNew). Defaults to auto-generated from workload_name. Migrating consumers should pass the old literal to avoid recreation."
}

variable "parameter_group_description" {
  type        = string
  default     = null
  description = "Override for the cluster parameter group description (ForceNew). Defaults to auto-generated from workload_name. Migrating consumers should pass the old literal to avoid recreation."
}

variable "replication_group_description" {
  type        = string
  default     = null
  description = "Override for the replication group description. Defaults to auto-generated from workload_name. In-place updatable on recent AWS providers."
}

variable "auth_secret_recovery_window_in_days" {
  type        = number
  default     = 30
  description = "Number of days AWS retains the AUTH token Secrets Manager secret after Terraform deletion. Set to 0 to force immediate deletion (non-recoverable) — useful for staging environments that are frequently torn down and rebuilt, since the 30-day AWS default blocks recreation under the same name for the recovery window. NOTE: AWS Secrets Manager exposes this only to DeleteSecret — changing it on an already-created secret produces a plan diff but does NOT mutate AWS-side state. The new value takes effect only the next time Terraform destroys this secret."

  validation {
    condition     = var.auth_secret_recovery_window_in_days == 0 || (var.auth_secret_recovery_window_in_days >= 7 && var.auth_secret_recovery_window_in_days <= 30)
    error_message = "auth_secret_recovery_window_in_days must be 0 (force delete) or between 7 and 30 days."
  }
}

variable "log_delivery_configurations" {
  type = list(object({
    destination      = string
    destination_type = string
    log_format       = string
    log_type         = string
  }))
  default     = []
  description = <<-EOT
    Optional log delivery configurations for Redis slow-log and/or
    engine-log. Each entry's `destination` is the CloudWatch log group
    name or Kinesis Firehose delivery-stream ARN; `destination_type` is
    "cloudwatch-logs" or "kinesis-firehose"; `log_format` is "json" or
    "text"; `log_type` is "slow-log" or "engine-log". CloudWatch log
    groups and Firehose streams must exist out-of-band; this module does
    not create them.
  EOT

  validation {
    condition = alltrue([
      for c in var.log_delivery_configurations : contains(["cloudwatch-logs", "kinesis-firehose"], c.destination_type)
    ])
    error_message = "log_delivery_configurations[*].destination_type must be one of: cloudwatch-logs, kinesis-firehose."
  }

  validation {
    condition = alltrue([
      for c in var.log_delivery_configurations : contains(["json", "text"], c.log_format)
    ])
    error_message = "log_delivery_configurations[*].log_format must be one of: json, text."
  }

  validation {
    condition = alltrue([
      for c in var.log_delivery_configurations : contains(["slow-log", "engine-log"], c.log_type)
    ])
    error_message = "log_delivery_configurations[*].log_type must be one of: slow-log, engine-log."
  }

  # ElastiCache allows at most one configuration per log_type. Catching
  # duplicates at plan time beats a cryptic AWS InvalidParameterCombination.
  validation {
    condition     = length(distinct([for c in var.log_delivery_configurations : c.log_type])) == length(var.log_delivery_configurations)
    error_message = "log_delivery_configurations may contain at most one entry per log_type (slow-log, engine-log)."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags to apply to all resources."
}
