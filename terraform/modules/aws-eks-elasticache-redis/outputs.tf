output "replication_group_id" {
  description = "ElastiCache replication group ID. Needed for out-of-band operations such as `aws elasticache modify-replication-group --auth-token-update-strategy ROTATE` (Scenario A rotation) and for authoring CloudWatch alarms scoped to this cluster."
  value       = aws_elasticache_replication_group.this.id
}

output "arn" {
  description = "Replication group ARN."
  value       = aws_elasticache_replication_group.this.arn
}

output "primary_endpoint" {
  description = "Primary endpoint address for writes (and reads on single-node clusters). On multi-node cluster-mode-disabled replication groups, application reads can alternatively use reader_endpoint for load-balanced reads."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint" {
  description = "Reader endpoint for load-balanced read traffic. Empty string when num_cache_clusters = 1 (no replicas)."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  # Read from the replication-group resource attribute (not var.port) so
  # the output tracks AWS-authoritative state, mirroring the same
  # treatment of `port` inside aws_secretsmanager_secret_version.auth's
  # secret_string. Functionally identical today (the resource's port is
  # wired from var.port upstream), but the symmetry eliminates a future
  # maintenance trap: if outputs and the secret payload sourced port
  # from different places, a maintainer could "harmonise" both onto
  # var.* and lose the AWS-authoritative property the secret_string
  # treatment depends on for `host`.
  description = "Redis TCP port. Read from the replication group's resource attribute so the output tracks AWS-authoritative state; the replication group binds to this port on primary and replica nodes."
  value       = aws_elasticache_replication_group.this.port
}

output "security_group_id" {
  description = "Replication group security group ID. Consumers attach this SG's ID to `allowed_security_group_ids` of peer modules that need to reach Redis, and reference it from their own egress rules to reach this cluster."
  value       = aws_security_group.this.id
}

output "parameter_group_name" {
  description = "Cluster parameter group name. Exposed for operator debugging (`aws elasticache describe-cache-parameters --cache-parameter-group-name ...`) and for consumers that want to layer additional parameter overrides."
  value       = aws_elasticache_parameter_group.this.name
}

output "auth_token_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the Redis AUTH token and connection metadata (host, port, password). Required for the Scenario A / B rotation runbooks inlined next to aws_secretsmanager_secret_version.auth in resources.tf. **CRITICAL**: attach read via `app_read_policy_arn`; do NOT inline the AUTH token into container environment variables."
  value       = aws_secretsmanager_secret.auth.arn
}

output "app_read_policy_arn" {
  description = "ARN of the IAM policy granting secretsmanager:GetSecretValue + DescribeSecret on the AUTH secret only. Attach to the consumer workload's IRSA role. `DescribeSecret` is required by External Secrets Operator and the Secrets Manager CSI driver; without it those integrations silently fail."
  value       = aws_iam_policy.app_read.arn
}

output "auth_secret_recovery_window_in_days" {
  description = "Echo of the recovery window (in days) applied to the AUTH secret. Useful for audit/plan review; AWS Secrets Manager enforces this at DeleteSecret time."
  value       = var.auth_secret_recovery_window_in_days
}
