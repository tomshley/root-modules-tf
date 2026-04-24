# 32 alphanumeric chars → ~190 bits of entropy, adequate for a bootstrap
# credential. `special = false` is a deliberate operational choice rather than
# a security one: Aurora PostgreSQL accepts a broad symbol set, but every tenant
# migrate Job that ingests this secret must either (a) treat the value as an
# opaque string at every call site or (b) correctly JSON/URL/shell-escape when
# the password contains `"`, `\`, `$`, or `%`. Keeping it alphanumeric
# eliminates an entire class of tenant-side escaping bugs. Revisit together
# with the tenant-side escaping contract, not in isolation.
resource "random_password" "master_password" {
  length  = 32
  special = false
}

resource "aws_db_subnet_group" "this" {
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

# Standalone ingress rules — one per allowed security group.
# Using aws_vpc_security_group_ingress_rule (not inline ingress {}) so that
# consumers can safely add their own rules to this SG without conflicts.
resource "aws_vpc_security_group_ingress_rule" "allowed" {
  for_each                     = toset(var.allowed_security_group_ids)
  security_group_id            = aws_security_group.this.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from allowed security group"

  depends_on = [aws_security_group.this]
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound"

  depends_on = [aws_security_group.this]
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.project_name_prefix}-${var.workload_name}-pg"
  family      = "aurora-postgresql${local.engine_major_version}"
  description = local.resolved_pg_description

  lifecycle {
    precondition {
      condition     = contains(["13", "14", "15", "16", "17"], local.engine_major_version)
      error_message = "engine_version must start with a supported Aurora PostgreSQL major version (13–17)."
    }
  }

  # --- Preset-resolved tunable parameters (only added when non-null) ---

  dynamic "parameter" {
    for_each = local.resolved_max_connections != null ? [local.resolved_max_connections] : []
    content {
      name         = "max_connections"
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }

  dynamic "parameter" {
    for_each = local.resolved_wal_buffers != null ? [local.resolved_wal_buffers] : []
    content {
      name         = "wal_buffers"
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }

  dynamic "parameter" {
    for_each = local.resolved_random_page_cost != null ? [local.resolved_random_page_cost] : []
    content {
      name  = "random_page_cost"
      value = parameter.value
    }
  }

  dynamic "parameter" {
    for_each = local.resolved_work_mem != null ? [local.resolved_work_mem] : []
    content {
      name  = "work_mem"
      value = parameter.value
    }
  }

  # --- Always-on audit parameters ---

  parameter {
    name  = "log_min_duration_statement"
    value = "300"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-pg"
  })
}

resource "aws_rds_cluster" "this" {
  cluster_identifier              = "${var.project_name_prefix}-${var.workload_name}-db"
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  database_name                   = var.database_name
  master_username                 = var.master_username
  master_password                 = random_password.master_password.result
  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  storage_encrypted               = true
  backup_retention_period         = var.backup_retention_period
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${var.project_name_prefix}-${var.workload_name}-final"
  copy_tags_to_snapshot           = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db"
  })

  # Symmetric with `ignore_changes = [secret_string]` on
  # aws_secretsmanager_secret_version.this below: after a Scenario A
  # (out-of-band) master-password rotation — see the three-scenario runbook
  # in the secret_version lifecycle comment — Terraform must not re-assert
  # `random_password.master_password.result` in-place on the cluster. Without
  # this, any subsequent apply that regenerates random_password (length bump,
  # resource replacement) would silently clobber the Postgres-side rotation
  # with a stale Terraform-state value. Terraform-driven rotation
  # (Scenario B) requires temporarily bypassing this ignore_changes; cluster
  # rebuild (Scenario C) is destructive and handled separately.
  lifecycle {
    ignore_changes = [master_password]
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier          = "${var.project_name_prefix}-${var.workload_name}-db-1"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db-1"
  })
}

resource "aws_rds_cluster_instance" "reader" {
  count = var.reader_instance_count

  identifier          = "${var.project_name_prefix}-${var.workload_name}-db-reader-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.this.id
  instance_class      = "db.serverless"
  engine              = aws_rds_cluster.this.engine
  engine_version      = aws_rds_cluster.this.engine_version
  publicly_accessible = false

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db-reader-${count.index + 1}"
  })
}

resource "aws_secretsmanager_secret" "this" {
  name                    = "${var.project_name_prefix}-${var.workload_name}-db"
  description             = "Cluster master (superuser) credentials for ${var.workload_name}. Do NOT attach read access to any runtime role — use the per-tenant policies produced from var.tenants (tenant_app_read_policy_arns for runtime, tenant_migrate_policy_arns for migrate Jobs)."
  recovery_window_in_days = var.master_secret_recovery_window_in_days

  tags = merge(var.tags, {
    Name = "${var.project_name_prefix}-${var.workload_name}-db"
  })
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master_password.result
    host     = aws_rds_cluster.this.endpoint
    port     = var.port
    dbname   = var.database_name
  })

  # secret_string is the initial bootstrap value. Three operational scenarios
  # need distinct procedures; pick the one that matches your goal. Do NOT
  # conflate them — scenario C destroys tenant data.
  #
  # SCENARIO A — Master-password rotation (happy path, NO data loss).
  #   This is the scenario `ignore_changes = [secret_string]` (here) and
  #   `ignore_changes = [master_password]` (on aws_rds_cluster.this) exist to
  #   enable. Rotate the password at the Postgres side and sync the secret.
  #   IMPORTANT: `aws secretsmanager put-secret-value` REPLACES the entire
  #   secret value — do NOT send a partial JSON that drops host/port/dbname
  #   or every tenant migrate Job + ESO sync will break silently. Use a
  #   read-modify-write pattern so all five fields (username, password,
  #   host, port, dbname) round-trip:
  #
  #     psql ... -c "ALTER USER <master_username> WITH PASSWORD '<new>';"
  #
  #     ARN=$(terraform output -raw master_secret_arn)
  #     # or directly: ARN="$(terraform output -raw <consumer-stack-alias>)"
  #     # e.g. `aurora_master_secret_arn` in the ami product stacks.
  #
  #     NEW=$(aws secretsmanager get-secret-value \
  #             --secret-id "$ARN" --query SecretString --output text \
  #           | jq -c --arg p '<new>' '.password = $p')
  #     aws secretsmanager put-secret-value \
  #       --secret-id "$ARN" --secret-string "$NEW"
  #
  #   Notes on the pipeline choice:
  #     - `jq -c` emits compact JSON (no pretty-print, no trailing newline
  #       stored in Secrets Manager).
  #     - Using a shell variable sidesteps macOS/BSD `xargs -I` replstr size
  #       caps (~255 bytes on older releases) that pretty-printed 5-field
  #       JSON can brush up against.
  #     - For extreme-length secrets or shells that choke on the quoted
  #       expansion, stage the jq output to a tmpfile and pass
  #       `--secret-string file://<path>` instead.
  #   The invariant is: read the current 5-field JSON, mutate only
  #   `.password`, write it back whole.
  #
  #   Subsequent `terraform apply` runs will NOT revert this. No -replace
  #   required. random_password.master_password.result in Terraform state is
  #   no longer authoritative after rotation — that is expected.
  #
  # SCENARIO B — Terraform-driven password rotation (data-preserving).
  #   Used when the operator wants Terraform to mint the new password (e.g.
  #   quarterly rotation via CI, not a human at a psql prompt). Requires
  #   temporarily bypassing the two ignore_changes blocks. Mechanic: -replace
  #   mints a new random_password.master_password.result, which propagates
  #   via normal in-place updates to aws_rds_cluster.this.master_password and
  #   aws_secretsmanager_secret_version.this.secret_string — but both of
  #   those updates would otherwise be silently dropped by the respective
  #   `ignore_changes` blocks. Lifting them lets the new value through:
  #     1. Comment out `ignore_changes = [master_password]` on
  #        aws_rds_cluster.this AND `ignore_changes = [secret_string]` here.
  #     2. terraform apply -replace=random_password.master_password
  #        (When called as a submodule, prefix: `-replace='module.<call>.random_password.master_password'`.)
  #        → Terraform drives an in-place ModifyDBCluster and overwrites the
  #        secret version. The cluster is NOT replaced; no data loss.
  #     3. Restore the two ignore_changes blocks and apply again.
  #   `terraform taint` is deprecated as of Terraform 0.15.2; use -replace.
  #
  # SCENARIO C — Cluster rebuild / disaster recovery (DESTRUCTIVE).
  #   This is NOT rotation. -replace=aws_rds_cluster.this forces
  #   DeleteDBCluster + CreateDBCluster and DESTROYS EVERY LOGICAL DATABASE
  #   ON THE CLUSTER, INCLUDING EVERY TENANT'S DATA. Use only for a deliberate
  #   rebuild from backup or a staging tear-down. Preconditions:
  #     - `deletion_protection = false` (otherwise DeleteDBCluster fails).
  #     - `skip_final_snapshot = true` OR a valid final_snapshot_identifier.
  #     - Every tenant has an acceptable backup; every tenant's migrate Job
  #       will need to re-bootstrap its logical DB + role after the rebuild.
  #   After those preconditions, the replacement command is:
  #     terraform apply \
  #       -replace=random_password.master_password \
  #       -replace=aws_rds_cluster.this \
  #       -replace=aws_secretsmanager_secret_version.this
  #   (Prefix every address with the module path when called as a submodule,
  #   e.g. `-replace='module.product_db.random_password.master_password'` —
  #   repeat for all three.)
  #
  # `replace_triggered_by = [aws_rds_cluster.this.arn]` fires only when the
  # cluster ARN actually changes (force-replacement: identifier rename via
  # project_name_prefix/workload_name change, db_subnet_group_name
  # recreation, or operator-driven `-replace=aws_rds_cluster.this`). Note
  # that Aurora engine major-version bumps with
  # `allow_major_version_upgrade = true` are in-place via ModifyDBCluster
  # and do NOT flip .arn; without that flag the provider rejects the plan
  # entirely rather than force-replacing. On the cases this DOES catch, the
  # secret's `host` is genuinely stale AND the cluster's master_password is
  # freshly minted from random_password.master_password.result anyway, so
  # writing the current secret_string value stays consistent with Postgres.
  #
  # DELIBERATELY ABSENT: a `terraform_data` or similar tripwire on var.port.
  # Any trigger that forces a fresh write of secret_string while the cluster
  # stays in place re-introduces the exact stale-state-password-overwrites-
  # live-Postgres-password failure mode that ignore_changes = [secret_string]
  # was added to prevent (after a Scenario A rotation). `var.port` edits
  # therefore require an operator-driven manual re-sync: Aurora applies the
  # new port in-place via ModifyDBCluster, then update only `.port` in the
  # master secret — preserving username/password/host/dbname — via the same
  # read-modify-write pattern as Scenario A (put-secret-value REPLACES the
  # entire secret value; a partial payload silently truncates the other
  # four fields and breaks every tenant migrate Job + ESO sync):
  #
  #     ARN=$(terraform output -raw master_secret_arn)
  #     NEW=$(aws secretsmanager get-secret-value \
  #             --secret-id "$ARN" --query SecretString --output text \
  #           | jq -c --argjson p <new_port> '.port = $p')
  #     aws secretsmanager put-secret-value \
  #       --secret-id "$ARN" --secret-string "$NEW"
  #   (Same pipeline rationale as Scenario A: `jq -c` for compact output, a
  #   shell variable instead of `xargs -I` to avoid BSD replstr caps, tmpfile
  #   + `--secret-string file://<path>` as the fallback for extreme lengths.)
  #
  # Tracked as a runbook item rather than a module-level automation because
  # port changes are rare and the cost of the silent-regression trap far
  # outweighs the convenience of auto-sync.
  #
  # CRITICAL: we reference `aws_rds_cluster.this.arn` rather than
  # `aws_rds_cluster.this`. A bare resource reference triggers replacement on
  # ANY planned change to the cluster — including routine in-place updates
  # (backup_retention_period, deletion_protection toggle, serverlessv2 scaling
  # edits, tag churn, etc.). That would silently overwrite any Scenario A
  # rotation on every such apply, nullifying the `ignore_changes` guarantee
  # above.
  lifecycle {
    ignore_changes       = [secret_string]
    replace_triggered_by = [aws_rds_cluster.this.arn]
  }
}

# ── Multi-tenant per-tenant resources ─────────────────────────────────────
# Only materialized when var.tenants is non-empty. Each tenant gets an empty
# Secrets Manager secret (populated later by a migrate Job) plus two IAM
# policies sized for a migrate-role + runtime-role split. See the
# var.tenants description for the threat-model rationale.

resource "aws_secretsmanager_secret" "tenant" {
  for_each = var.tenants

  name                    = "${var.project_name_prefix}-${var.workload_name}-${each.key}-app-db"
  description             = "Per-tenant app credentials for ${each.key} on ${var.workload_name} cluster. Populated by the tenant's migrate Job — not by Terraform."
  recovery_window_in_days = var.tenant_secret_recovery_window_in_days

  tags = merge(var.tags, {
    Name   = "${var.project_name_prefix}-${var.workload_name}-${each.key}-app-db"
    Tenant = each.key
  })
}

# Runtime (app) policy — read-only on the tenant's own app secret.
# Attach to the tenant's long-running runtime IRSA role.
resource "aws_iam_policy" "tenant_app_read" {
  for_each = var.tenants

  name        = "${var.project_name_prefix}-${var.workload_name}-${each.key}-app-read"
  description = "Read access to the ${each.key} app secret on ${var.workload_name} cluster."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTenantAppSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
        ]
        Resource = [aws_secretsmanager_secret.tenant[each.key].arn]
      }
    ]
  })

  tags = merge(var.tags, {
    Name   = "${var.project_name_prefix}-${var.workload_name}-${each.key}-app-read"
    Tenant = each.key
  })
}

# Migrate Job policy — reads the cluster master secret to bootstrap the
# per-tenant Postgres role + logical DB, then populates the tenant's app
# secret with the scoped credentials it just created. Attach to the
# tenant's migrate-Job IRSA role; do NOT attach to the runtime role.
resource "aws_iam_policy" "tenant_migrate" {
  for_each = var.tenants

  name        = "${var.project_name_prefix}-${var.workload_name}-${each.key}-migrate"
  description = "Migrate-Job access for ${each.key}: read master secret for bootstrap, populate tenant app secret."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadMasterForBootstrap"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
        ]
        Resource = [aws_secretsmanager_secret.this.arn]
      },
      {
        Sid    = "PopulateTenantAppSecret"
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
        ]
        Resource = [aws_secretsmanager_secret.tenant[each.key].arn]
      },
    ]
  })

  tags = merge(var.tags, {
    Name   = "${var.project_name_prefix}-${var.workload_name}-${each.key}-migrate"
    Tenant = each.key
  })
}
