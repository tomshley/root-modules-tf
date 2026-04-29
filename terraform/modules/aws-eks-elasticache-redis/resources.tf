# 32 alphanumeric chars → ~190 bits of entropy, comfortably above the
# ElastiCache AUTH minimum of 16 and below the 128-byte maximum.
# `special = false` is a deliberate operational choice: ElastiCache AUTH
# accepts a broad printable-ASCII set, but every consumer of this secret
# (Spring Boot Lettuce/Jedis clients, Go go-redis, Python redis-py, curl
# smoke-tests, k8s ExternalSecret templating) must either (a) treat the
# value as an opaque string at every call site or (b) correctly JSON /
# URL / shell-escape when the password contains characters that would
# need quoting. Alphanumeric-only eliminates an entire class of consumer-
# side escaping bugs and is consistent with the Aurora module's password
# generation. Revisit in concert with the consumer-side escaping
# contract, not in isolation.
#
# ElastiCache additionally forbids `@`, `"`, `/`, and space in AUTH
# tokens; `special = false` avoids all four by construction, so no
# `override_special` is needed.
#
# DELIBERATELY no `keepers = {}`: regeneration is operator-driven via
# `-replace=random_password.auth_token` (Scenario B in the inline
# runbook). A keepers map wired to, say, `var.engine_version` would
# silently rotate the AUTH token on routine minor-version bumps —
# exactly the failure mode we document against in the replication
# group's `ignore_changes = [auth_token]` block.
resource "random_password" "auth_token" {
  length  = 32
  special = false
}

resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name_prefix}-${var.workload_name}"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}"
  })
}

resource "aws_security_group" "this" {
  name        = "${var.project_name_prefix}-${var.workload_name}"
  description = local.resolved_sg_description
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}"
  })
}

# Standalone ingress rules — one per allowed security group. Using
# aws_vpc_security_group_ingress_rule (not inline ingress {}) so that
# consumers can safely add their own rules to this SG without conflicts,
# and keying by SG ID (for_each = toset(...)) so add/remove is surgical
# and there are no index-shift races on list mutation. Same pattern as
# aws-eks-aurora-cluster: the InvalidPermission race noted on the
# `depends_on` below was observed there in v1.5.4 with the prior
# list-based shape, and the for_each-keyed shape adopted here landed in
# v1.5.6+ to eliminate the index-shift class of churn.
resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each                     = toset(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "Redis from allowed security group"

  # The `security_group_id = aws_security_group.this.id` attribute
  # reference already establishes a DAG edge to the SG. The explicit
  # depends_on is retained for symmetry with the Aurora module
  # (aws-eks-aurora-cluster v1.5.4) which observed a concrete
  # InvalidPermission race during in-place updates where OpenTofu
  # resolved the SG ID from state and parallelised standalone rule
  # CREATEs against SG mutation. ElastiCache has not been observed to
  # hit the same race, but the cost of an extra edge is negligible and
  # the operator blast radius on a re-occurrence is high (ingress churn
  # across every consumer of the Redis SG).
  depends_on = [aws_security_group.this]
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"

  # See the symmetric comment on aws_vpc_security_group_ingress_rule.allowed.
  depends_on = [aws_security_group.this]
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "${var.project_name_prefix}-${var.workload_name}-pg"
  family      = var.parameter_group_family
  description = local.resolved_pg_description

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-pg"
  })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project_name_prefix}-${var.workload_name}"
  description          = local.resolved_rg_description
  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = var.port
  subnet_group_name    = aws_elasticache_subnet_group.this.name
  security_group_ids   = [aws_security_group.this.id]
  parameter_group_name = aws_elasticache_parameter_group.this.name

  # HA flags derived from num_cache_clusters. num_cache_clusters >= 2 is
  # both necessary and sufficient for Multi-AZ + automatic failover on a
  # cluster-mode-disabled replication group. Deriving these flags removes
  # a class of "multi_az_enabled = true but num_cache_clusters = 1"
  # misconfigurations that would otherwise fail at apply with a cryptic
  # AWS error.
  multi_az_enabled           = local.ha_enabled
  automatic_failover_enabled = local.ha_enabled

  # Encryption — hardcoded defaults, not variables, because toggling
  # either is ForceNew on the replication group and the secure shape is
  # the only supported shape. `transit_encryption_mode = "required"`
  # rejects unencrypted clients; the default would allow both encrypted
  # and unencrypted connections ("preferred"), which defeats the purpose
  # of enabling transit encryption in the first place. Requires aws
  # provider 5.22+ (see provider.tf comment).
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  kms_key_id                 = var.kms_key_id
  auth_token                 = random_password.auth_token.result

  maintenance_window         = var.maintenance_window
  snapshot_retention_limit   = var.snapshot_retention_limit
  snapshot_window            = var.snapshot_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  final_snapshot_identifier = var.final_snapshot_identifier
  notification_topic_arn    = var.notification_topic_arn

  dynamic "log_delivery_configuration" {
    for_each = var.log_delivery_configurations
    content {
      destination      = log_delivery_configuration.value.destination
      destination_type = log_delivery_configuration.value.destination_type
      log_format       = log_delivery_configuration.value.log_format
      log_type         = log_delivery_configuration.value.log_type
    }
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}"
  })

  # Symmetric with `ignore_changes = [secret_string]` on
  # aws_secretsmanager_secret_version.auth below: after a Scenario A
  # (out-of-band) AUTH token rotation — see the three-scenario runbook
  # next to the secret version — Terraform must not re-assert
  # `random_password.auth_token.result` in-place on the replication
  # group. Without this, any subsequent apply that regenerates
  # random_password (length bump, resource replacement) would silently
  # clobber the Redis-side rotation with a stale Terraform-state value.
  # Terraform-driven rotation (Scenario B) requires temporarily
  # bypassing this ignore_changes; cluster rebuild (Scenario C) is
  # destructive and handled separately.
  lifecycle {
    ignore_changes = [auth_token]
  }
}

resource "aws_secretsmanager_secret" "auth" {
  name                    = "${var.project_name_prefix}-${var.workload_name}-redis"
  description             = "Redis AUTH token and connection metadata (host, port, password) for ${var.workload_name}. Attach read access via the ${var.project_name_prefix}-${var.workload_name}-redis-read IAM policy produced by this module — do NOT inline the AUTH token into container environment variables. Inject at runtime via External Secrets Operator or the Secrets Manager CSI driver."
  recovery_window_in_days = var.auth_secret_recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-redis"
  })
}

resource "aws_secretsmanager_secret_version" "auth" {
  secret_id = aws_secretsmanager_secret.auth.id
  # Both `host` and `port` read from the replication-group resource (not
  # from var.* directly) so the secret value tracks AWS-authoritative
  # state rather than the input variable. `port = var.port` would be
  # functionally identical today (the resource's port is wired from
  # var.port upstream), but the asymmetry would invite a future
  # maintainer to "harmonise" both fields onto var.* and lose the
  # AWS-authoritative property of `host`.
  secret_string = jsonencode({
    host     = aws_elasticache_replication_group.this.primary_endpoint_address
    port     = aws_elasticache_replication_group.this.port
    password = random_password.auth_token.result
  })

  # secret_string is the initial bootstrap value. Three operational
  # scenarios need distinct procedures; pick the one that matches your
  # goal. Do NOT conflate them — scenario C destroys the Redis dataset.
  #
  # SUBMODULE INVOCATION NOTE — applies to every shell snippet below.
  #   `terraform output -raw replication_group_id` and
  #   `terraform output -raw auth_token_secret_arn` resolve against the
  #   ROOT module's outputs. When this module is invoked as a submodule
  #   (the normal case, e.g. `module.app_redis`), consumer stacks must
  #   re-export the values they want operators to be able to read at the
  #   root, e.g.
  #     output "app_redis_replication_group_id" {
  #       value = module.app_redis.replication_group_id
  #     }
  #     output "app_redis_auth_token_secret_arn" {
  #       value = module.app_redis.auth_token_secret_arn
  #     }
  #   and operators substitute those re-exported names into the snippets.
  #   Alternatively, fetch via:
  #     terraform output -json | jq -r '.app_redis_replication_group_id.value'
  #   The same submodule-prefix rule applies to `-replace=...` addresses
  #   in scenarios B and C (already documented inline below).
  #
  # SCENARIO A — AUTH token rotation (happy path, NO data loss).
  #   This is the scenario `ignore_changes = [secret_string]` (here) and
  #   `ignore_changes = [auth_token]` (on aws_elasticache_replication_group.this)
  #   exist to enable. Rotate the token on the ElastiCache side and sync
  #   the secret. IMPORTANT: `aws secretsmanager put-secret-value`
  #   REPLACES the entire secret value — do NOT send a partial JSON that
  #   drops host/port or every consumer that reads those fields will
  #   break silently. Use a read-modify-write pattern so all three
  #   fields (host, port, password) round-trip:
  #
  #     # Mint the new token once and reuse via a shell variable. Typing
  #     # `<new>` literally in two places is an easy desync: ElastiCache
  #     # accepts the modify-replication-group value while the secret
  #     # stores whatever the operator typed into `--arg p`, and
  #     # consumers then fail auth silently against Redis with no
  #     # plan-time signal.
  #     NEW_TOKEN='<paste-new-32+-char-alphanumeric-token-here>'
  #
  #     aws elasticache modify-replication-group \
  #       --replication-group-id "$(terraform output -raw replication_group_id)" \
  #       --auth-token "$NEW_TOKEN" \
  #       --auth-token-update-strategy ROTATE \
  #       --apply-immediately
  #
  #     ARN=$(terraform output -raw auth_token_secret_arn)
  #     NEW=$(aws secretsmanager get-secret-value \
  #             --secret-id "$ARN" --query SecretString --output text \
  #           | jq -c --arg p "$NEW_TOKEN" '.password = $p')
  #     aws secretsmanager put-secret-value \
  #       --secret-id "$ARN" --secret-string "$NEW"
  #
  #   Notes on the pipeline choice:
  #     - `jq -c` emits compact JSON (no pretty-print, no trailing
  #       newline stored in Secrets Manager).
  #     - Using a shell variable sidesteps macOS/BSD `xargs -I` replstr
  #       size caps (~255 bytes on older releases).
  #     - For extreme-length tokens or shells that choke on the quoted
  #       expansion, stage the jq output to a tmpfile and pass
  #       `--secret-string file://<path>` instead.
  #   The invariant is: read the current 3-field JSON, mutate only
  #   `.password`, write it back whole.
  #
  #   `--auth-token-update-strategy ROTATE` permits both the old and new
  #   tokens during a grace window so in-flight connections are not
  #   severed; use `SET` for immediate cutover when the dual-auth window
  #   is unacceptable (e.g. after suspected credential compromise).
  #
  #   Subsequent `terraform apply` runs will NOT revert this. No
  #   -replace required. `random_password.auth_token.result` in
  #   Terraform state is no longer authoritative after rotation — that
  #   is expected.
  #
  #   CAVEAT — Scenario A and identifier rename:
  #   An identifier rename (change to `project_name_prefix` or
  #   `workload_name`) flips the replication group's ARN and triggers
  #   `replace_triggered_by` on this secret version. A rename apply
  #   replaces the entire Redis replication group (new AWS resource
  #   with fresh `auth_token = random_password.auth_token.result`) and
  #   rewrites this secret from the same state value; both sides
  #   return to Terraform-authoritative credentials. Any prior
  #   Scenario A rotation is discarded, which is correct because the
  #   cluster the rotation applied to no longer exists. If you want
  #   to carry a specific token across a rename, rotate it BEFORE the
  #   rename apply by running Scenario B (`-replace=random_password`)
  #   so the new value is in state, then do the rename.
  #
  # SCENARIO B — Terraform-driven rotation (data-preserving).
  #   Used when the operator wants Terraform to mint the new token
  #   (e.g. quarterly rotation via CI, not a human at the CLI). Requires
  #   temporarily bypassing the two ignore_changes blocks. Mechanic:
  #   -replace mints a new random_password.auth_token.result, which
  #   propagates via normal in-place updates to
  #   aws_elasticache_replication_group.this.auth_token and
  #   aws_secretsmanager_secret_version.auth.secret_string — but both of
  #   those updates would otherwise be silently dropped by the
  #   respective `ignore_changes` blocks. Lifting them lets the new
  #   value through:
  #     1. Comment out `ignore_changes = [auth_token]` on the
  #        replication group AND `ignore_changes = [secret_string]`
  #        here.
  #     2. terraform apply -replace=random_password.auth_token
  #        (When called as a submodule, prefix:
  #        `-replace='module.<call>.random_password.auth_token'`.)
  #        → Terraform drives an in-place ModifyReplicationGroup (using
  #        whatever auth_token_update_strategy the provider defaults
  #        to; aws ~> 5.x defaults to ROTATE) and overwrites the secret
  #        version. The replication group is NOT replaced; no data
  #        loss.
  #     3. Restore the two ignore_changes blocks and apply again.
  #   `terraform taint` is deprecated as of Terraform 0.15.2; use
  #   -replace.
  #
  # SCENARIO C — Replication group rebuild / disaster recovery (DESTRUCTIVE).
  #   This is NOT rotation.
  #   -replace=aws_elasticache_replication_group.this forces
  #   DeleteReplicationGroup + CreateReplicationGroup and DESTROYS THE
  #   CACHED DATASET. For pure cache workloads this is an inconvenience;
  #   for session stores, OTP state, JWT denylists, rate-limit counters,
  #   it invalidates every user's session and state simultaneously.
  #   Preconditions:
  #     - Explicit acknowledgement of dataset loss, OR a
  #       `final_snapshot_identifier` set on the replication group plus
  #       a documented restore plan.
  #   After those preconditions, the replacement command is:
  #     terraform apply \
  #       -replace=random_password.auth_token \
  #       -replace=aws_elasticache_replication_group.this \
  #       -replace=aws_secretsmanager_secret_version.auth
  #   (Prefix every address with the module path when called as a
  #   submodule.)
  #
  # `replace_triggered_by = [aws_elasticache_replication_group.this.arn]`
  # fires only when the replication group ARN actually changes
  # (force-replacement). The triggers are:
  #   - identifier rename (project_name_prefix or workload_name change)
  #   - var.port change (ForceNew on aws_elasticache_replication_group.port —
  #     AWS does not support modifying the port; verified in
  #     terraform-provider-aws/internal/service/elasticache/replication_group.go,
  #     and `aws elasticache modify-replication-group` has no --port)
  #   - subnet_group_name recreation
  #   - operator-driven `-replace=aws_elasticache_replication_group.this`
  # Engine major-version bumps are in-place via ModifyReplicationGroup
  # and do NOT flip .arn. On the cases this DOES catch, the secret's
  # `host` is genuinely stale AND the replication group's auth_token is
  # freshly minted from random_password.auth_token.result anyway, so
  # writing the current secret_string value stays consistent with
  # Redis. (For the var.port-change case specifically, random_password
  # is NOT replaced, so the AUTH token is preserved across the rebuild
  # even though the dataset is not.)
  #
  # `var.port` edits — DESTRUCTIVE; no manual secret re-sync needed.
  # Unlike the symmetric `var.port` runbook in aws-eks-aurora-cluster
  # (where Aurora supports in-place ModifyDBCluster --port and the
  # cluster ARN does not change, so the operator must hand-write the
  # new port back into the master secret), an ElastiCache port change
  # destroys the replication group AND its dataset, then creates a
  # fresh one on the new port — operationally equivalent to Scenario C.
  # The replace_triggered_by above replaces this secret_version
  # automatically and the new value reads the new replication group's
  # host/port plus the preserved AUTH token from
  # random_password.auth_token.result; no operator-driven jq
  # read-modify-write is required, and any such mutation between plan
  # and apply would race the automatic replacement. Operators MUST
  # treat a `var.port` change with the Scenario C preconditions
  # (explicit acknowledgement of dataset loss, OR
  # `final_snapshot_identifier` plus a documented restore plan).
  #
  # CAVEAT — var.port change and prior Scenario A rotation:
  # Symmetric with the rename caveat in Scenario A above. Any prior
  # Scenario A (out-of-band) AUTH token rotation was applied to the
  # OLD replication group, which the var.port rebuild destroys — the
  # rotated token is bound to a cluster that no longer exists. The new
  # replication group is created with
  # `auth_token = random_password.auth_token.result` (the original,
  # never-rotated value), and the secret is rewritten from that same
  # state value, so the prior Scenario A rotation is silently
  # discarded. This is correct (the cluster the rotation applied to
  # is gone), but it is also a plausible incident-response sequence
  # (port restriction following a network exposure finding, applied
  # after credentials were rotated out-of-band). Operators who want
  # to carry a specific token across a port change should run
  # Scenario B (`-replace=random_password.auth_token`) BEFORE the
  # port change so the new value is in state, then change the port.
  #
  # CRITICAL: we reference `aws_elasticache_replication_group.this.arn`
  # rather than the bare resource. A bare resource reference triggers
  # replacement on ANY planned change — including routine in-place
  # updates (snapshot window edits, parameter group name edits, tag
  # churn). That would silently overwrite any Scenario A rotation on
  # every such apply, nullifying the `ignore_changes` guarantee above.
  lifecycle {
    ignore_changes       = [secret_string]
    replace_triggered_by = [aws_elasticache_replication_group.this.arn]
  }
}

# App-runtime policy — read-only on the Redis AUTH secret. Attach to the
# consumer workload's IRSA role. Redis has no "superuser" vs "app user"
# split the way Postgres does (AUTH is a single-token bearer mechanism),
# so there is no separate migrate-vs-app policy pair: the same policy
# covers every consumer that needs to read the AUTH token.
resource "aws_iam_policy" "app_read" {
  name        = "${var.project_name_prefix}-${var.workload_name}-redis-read"
  description = "Read access to the ${var.workload_name} Redis AUTH token secret."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadRedisAuthSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
        ]
        Resource = [aws_secretsmanager_secret.auth.arn]
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-redis-read"
  })
}
