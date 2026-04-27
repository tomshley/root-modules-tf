# Changelog

All notable changes to this project are documented in this file.

This project follows Semantic Versioning.

---

## [1.8.0] — 2026-04-27

### Features

- **confluent-streaming-topics**: Add optional `delete_retention_ms` and `min_compaction_lag_ms` fields to `catalog_entries` and emit them as Kafka `delete.retention.ms` / `min.compaction.lag.ms` topic configs when non-null. Both default to null and are omitted from the topic config in the null case, so existing consumers continue to land Kafka's defaults (24h tombstone retention, 0ms minimum compaction lag) — fully additive on existing catalogs. The previous shape silently dropped these fields at the `list(object({...}))` type-coercion boundary in the consumer's `module` call: catalogs declaring `delete_retention_ms: 604800000` (7d) for compacted+delete topics never propagated to Confluent and the broker applied the 24h default instead, narrowing the tombstone observation window for downstream change-log / CDC consumers without any plan-time signal. Operationally relevant for any consumer following the `cleanup_policy = "compact,delete"` pattern (state-changelog topics, session/auth denylists, tenant changelog streams, CDC source topics) where the 24h default would silently break consumers that pause longer than a day.
- **confluent-streaming-topics**: Add plan-time validation that rejects `delete_retention_ms` and `min_compaction_lag_ms` on topics whose `cleanup_policy` does not include `"compact"`. Kafka silently ignores both fields on pure-delete topics, so a misconfiguration would land inert on the broker with no signal — exactly the failure shape this module's other plan-time validations exist to prevent. Implemented via `strcontains(t.cleanup_policy, "compact")` so both `"compact"` and `"compact,delete"` pass; only `"delete"` is rejected.

### Fixed (code-review pass 2)

- **confluent-streaming-topics** (MEDIUM): Broaden the `cleanup_policy` enum to accept `"delete,compact"` in addition to `"compact,delete"`. Kafka treats `cleanup.policy` as an order-agnostic comma-separated list and accepts both orderings at the broker; the Apache Kafka and Confluent Cloud / Platform docs explicitly use `"delete,compact"` as the canonical example form. The pass-1 enum (`["delete", "compact", "compact,delete"]`) inadvertently rejected the documentation-default form, so an operator copying directly from upstream Kafka docs into a catalog YAML would have hit an unexpected plan-time rejection with no documented mitigation. The pass-1 inline comment also claimed "Kafka's three accepted values" — factually wrong; there are at least four canonical comma-list forms. Comment rewritten to document Kafka's order-agnostic semantics and the rationale for accepting both orderings; error message broadened to list all four forms.
- **confluent-streaming-topics** (NIT): Correct the `tostring()` defense comment in `resources.tf::confluent_kafka_topic.managed.config`. The pass-1 wording said the omitted-`tostring` failure mode was `"number expected, string found"`; the actual direction is the inverse — `confluent_kafka_topic.config` expects strings, so supplying numbers would surface as `"string required"` when the merged `map(any)` result is assigned to the resource's `map(string)`-typed config attribute. Substantively `tostring()` is still required (the cleanup.policy + retention.ms entries in the same map are strings, so without `tostring()` on the new optional fields the unified value type is `any` and downstream coercion to `map(string)` is the layer that fails); only the wording was inverted.
- **examples/streaming-full-stack** (NIT): Change `topic-gamma-state.min_compaction_lag_ms` from `0` (Kafka's broker default) to `60000` (1 minute) with an inline comment explaining the changelog-restore use case. The pass-1 example set the field to its default, producing a `"min.compaction.lag.ms" = "0"` config row that is operationally identical to omitting the field — a reader copying the pattern would not see what the field is *for*. The new value is a meaningful non-default that demonstrates a typical production tuning for compacted state-changelog topics (delay compaction long enough that changelog-restore consumers observe the producer's record-then-tombstone sequence rather than a pre-compacted view).

### Fixed (code-review pass 1)

- **confluent-streaming-topics** (LOW): Add plan-time `>= 0` range validation on the new `delete_retention_ms` and `min_compaction_lag_ms` fields. Kafka's broker enforces `Range.atLeast(0)` on both `delete.retention.ms` and `min.compaction.lag.ms`; without these gates a negative value would otherwise fall through plan and surface as a cryptic Confluent provider error minutes into apply. Mirrors the closest-to-operator-feedback pattern used by the rest of the module's plan-time validations.
- **confluent-streaming-topics** (NIT): Add plan-time enum validation on `cleanup_policy`, restricting it to Kafka's canonical comma-list forms (see pass-2 broadening above). Pre-existing gap in the module's validation coverage that became newly load-bearing once the `compact`-substring gates landed: a typo like `"compaction"` would slip past `strcontains(_, "compact")` (the new gate) AND past Kafka's allowlist at apply, surfacing only as a cryptic provider error. With the enum gate in front, the substring gates are now constrained to a known-safe value space.
- **confluent-streaming-topics** (NIT): Switch the two `compact`-presence checks from `can(regex("compact", t.cleanup_policy))` to `strcontains(t.cleanup_policy, "compact")` for intent clarity. Functionally identical; the module already requires Terraform 1.5+ / OpenTofu 1.6+ for `strcontains` (and pins `>= 1.9` in `provider.tf` for the broader cross-variable validation pattern used elsewhere in the repo).
- **examples/streaming-full-stack** (NIT): Extend `catalogs/streaming/services/service-b/core.yaml` with a second topic (`topic-gamma-state`) demonstrating the optional `cleanup_policy = "compact,delete"` + `delete_retention_ms = 604800000` (7d) shape. Until this entry, the optional fields were documented in the module README and the `[Unreleased]` CHANGELOG block but had no concrete YAML reference in any in-repo example, so a consumer copying the example pattern wouldn't see the round-trip from YAML through `yamldecode` → `merge()` → module input.

### Backward Compatibility

Fully additive on the `catalog_entries` schema — the two new fields are `optional(number)` with no default, so existing consumers that omit them in YAML continue to round-trip through `yamldecode` → `merge()` → object-type coercion exactly as before. Existing tagged consumers pinned at prior releases remain unaffected; consumers that want to honour the two compaction-tuning fields must repin to this release and may then add the fields to their catalog YAMLs without further code changes.

**Newly enforced (potential plan-time break for malformed catalogs):** the new `cleanup_policy` enum validation will reject any pre-existing typo (e.g. `"compact, delete"` with a stray space, `"compaction"`) at plan time. Both order-agnostic Kafka-canonical forms (`"compact,delete"` and `"delete,compact"`) are accepted as of pass 2; only whitespace-bearing or misspelled forms are rejected. Such configurations would have failed at apply against Kafka anyway, but the failure point now moves earlier and the error message is actionable. Verify with `tofu validate` against your existing catalogs before upgrading.

---

## [1.7.0] — 2026-04-27

### Features

- **aws-eks-elasticache-redis**: New module provisioning an AWS ElastiCache Redis replication group with the secure shape as the only shape: at-rest encryption hardcoded on (customer-managed KMS via `var.kms_key_id` or the AWS-managed `alias/aws/elasticache`), transit encryption hardcoded on with `transit_encryption_mode = "required"` (rejects unencrypted clients — the AWS default `"preferred"` does not), AUTH token generated via `random_password` (32 alphanumeric chars — meets ElastiCache's 16-byte minimum, avoids the forbidden `@`, `"`, `/`, space set, and eliminates consumer-side escaping bugs). The AUTH token and connection metadata (`host`, `port`, `password`) are written to a Secrets Manager secret with `lifecycle { ignore_changes = [secret_string], replace_triggered_by = [aws_elasticache_replication_group.this.arn] }`, symmetric with the Aurora module's secret-version treatment so operators can rotate the AUTH token out-of-band without subsequent applies silently reverting the rotation. `ignore_changes = [auth_token]` on the replication group closes the mirror side of that invariant. Multi-AZ and automatic failover are derived from `num_cache_clusters >= 2` rather than exposed as independent flags, eliminating the class of "multi_az_enabled = true but num_cache_clusters = 1" misconfigurations that would otherwise fail at apply with a cryptic AWS error. The module also produces a least-privilege IAM policy (`secretsmanager:GetSecretValue` + `DescribeSecret` on the AUTH secret only) for attachment to consumer IRSA roles; `DescribeSecret` is required by External Secrets Operator and the Secrets Manager CSI driver and would silently break those integrations if omitted.
- **aws-eks-elasticache-redis**: Add variable validations for `workload_name` (regex + length check against the 40-byte ElastiCache `replication_group_id` limit, cross-variable reference to `project_name_prefix` — requires Terraform 1.9+ / OpenTofu 1.8+), the generated `-redis-read` IAM policy name (128-byte AWS IAM limit, cross-variable), `engine_version` (Redis 7.x only — pinned minor or the AWS-native `7.x` alias; Redis 6.x is deliberately rejected because `transit_encryption_mode = "required"` requires engine 7.0.5+), `parameter_group_family` (`redis7` only, same rationale), `num_cache_clusters` (1-6, AWS limit for cluster-mode-disabled), `port` (TCP 1-65535), `maintenance_window` (`ddd:hh24:mi-ddd:hh24:mi` with hour 00-23), `snapshot_retention_limit` (0-35 days), `snapshot_window` (`hh24:mi-hh24:mi` with hour 00-23), `auth_secret_recovery_window_in_days` (0 or 7-30), and `log_delivery_configurations` (destination_type, log_format, log_type enum membership, and the AWS-enforced "at most one entry per log_type" rule — caught at plan time rather than as a cryptic `InvalidParameterCombination`).
- **aws-eks-elasticache-redis**: Declare `required_version = ">= 1.9"` in `provider.tf` to enforce the Terraform 1.9 / OpenTofu 1.8 floor required by the cross-variable validation blocks above. Without this declaration, older CLIs emit a cryptic `Variables not allowed` parse error pointed at the validation block rather than an actionable "upgrade your CLI" message. The `transit_encryption_mode = "required"` attribute additionally requires aws provider 5.22+; the module's `~> 5.0` constraint is intentionally permissive to stay consistent with the rest of the repo, so consumer stacks should lock to 5.22+ in their `.terraform.lock.hcl`.
- **aws-eks-elasticache-redis**: Inline three-scenario AUTH token rotation runbook next to `aws_secretsmanager_secret_version.auth` in `resources.tf`, parallel to the Aurora module's secret rotation runbook. Scenario A is out-of-band rotation via `aws elasticache modify-replication-group --auth-token-update-strategy ROTATE` + `aws secretsmanager put-secret-value` with a read-modify-write jq pattern that preserves all three fields (`host`, `port`, `password`) — partial payloads silently truncate the secret. Scenario B is Terraform-driven rotation via `-replace=random_password.auth_token` with temporary bypass of the two `ignore_changes` blocks; the replication group is NOT replaced. Scenario C is replication-group rebuild (`-replace=aws_elasticache_replication_group.this`), explicitly destructive and documented separately — relevant for session stores, OTP state, JWT denylists, rate-limit counters where invalidating the dataset breaks every user simultaneously.
- **examples/aws-eks-elasticache-redis-standalone**: New example showing a single-node Redis replication group sized for development and smoke tests, with `auth_secret_recovery_window_in_days = 0` to permit immediate workload-name recreation during frequent tear-down cycles.
- **examples/aws-eks-elasticache-redis-multi-az**: New example showing a two-node Multi-AZ replication group with automatic failover, 7-day snapshot retention, optional SNS event notifications, optional CloudWatch slow-log delivery, and per-workload IRSA composition via `for_each` over a workloads map — mirroring the `aws-eks-aurora-multi-tenant` pattern so operators familiar with one example can read the other.

### Toolbox

- **render-service-bundle.sh**: Add `portal` service branch. Portal uses the multi-tenant product-cluster Aurora pattern (one DB per service on a shared cluster), so its `aws.env` ships APP and MIGRATE IRSA separately (read from the `product_tenant_app_role_arns` / `product_tenant_migrate_role_arns` / `product_tenant_secret_arns` map outputs via `tofu output -json` + `jq`) alongside `REDIS_AUTH_SECRET_ARN`, `APPSTREAM_ROLE_ARN`, and the ACM cert ARN (preferring a portal-specific `portal_certificate_arn` when the consumer provisioned one, falling back to the shared ingress `certificate_arn` when portal is attached as a SAN). The portal branch also writes `db-config.env` (product-cluster endpoint, portal tenant DB name, `ssl=require`), `db.env` (populated from the portal tenant app secret — NOT the cluster master — with a clear skip-with-warning when the secret is empty because the migrate Job has not yet run; using the master secret would grant portal runtime cluster-superuser access and violate the multi-tenant threat model), `redis.env` (connection metadata only; the AUTH token stays in Secrets Manager and is injected at runtime via ExternalSecrets / Secrets Manager CSI using `REDIS_AUTH_SECRET_ARN`), and the standard `rds-ca-bundle.pem` + `rds-cert.env` pair. Portal skips the `kafka.env` and `s3-config.env` branches (no Kafka or S3 interaction).

### Fixed (code-review pass 6)

- **render-service-bundle.sh** (MEDIUM): Correct the failure-mode messaging on the portal `db.env` rendering branch. Pre-pass-6 the inline comment block claimed the inner `if/else` ("portal tenant secret not populated yet — run the portal migrate Job first") handled the migrate-Job-has-not-yet-run case while the outer `else` ("could not read Secrets Manager: $APP_SECRET_ARN") handled IAM/network failures, but the runtime mapping was the reverse: the Aurora module creates `aws_secretsmanager_secret.tenant` with no `aws_secretsmanager_secret_version`, so until the migrate Job runs `aws secretsmanager get-secret-value` returns `ResourceNotFoundException` ("can't find the specified secret value for staging label: AWSCURRENT"), `SECRET_JSON` is rescued to an empty string by `2>/dev/null || echo ""`, and the **outer** `else` fires — surfacing a message that suggests an IAM/network problem when the actual cause is just "the migrate Job hasn't run yet". The first time portal is rendered post-cluster-bootstrap and pre-first-migrate (the most common bootstrap order), an operator following the previous message would chase phantom IRSA/VPCE/SCP issues. The outer-else message now leads with the most likely cause (migrate not yet run, secret has no version) and lists the rarer IAM/network/KMS Decrypt causes after; the inner-else message clarifies that it covers the atypical "version exists but missing username/password" defense-in-depth shape only. The comment block above the `aws secretsmanager get-secret-value` invocation was rewritten with an accurate failure-mode mapping table cross-referencing the Aurora module's tenant-secret bootstrap shape.
- **CHANGELOG.md** (NIT): Reorder the `[Unreleased]` block's `Fixed (code-review pass …)` headers into reverse-chronological order (6, 5, 4, 3, 2, 1). Pre-pass-6 the order was `5, 4, 1, 3, 2`, which inverted the convention used everywhere else in this file. A reviewer scanning by descending pass number was thrown by the dip-and-recover; the rearranged ordering makes the chronology unambiguous.

### Fixed (code-review pass 5)

- **aws-eks-elasticache-redis** (MEDIUM): Extend the `var.port`-change runbook in `resources.tf` with an explicit Scenario A interaction caveat, parallel to the existing rename caveat in Scenario A. A `var.port` edit triggers the same `replace_triggered_by` rebuild path as an identifier rename, so any prior Scenario A (out-of-band) AUTH token rotation is silently discarded — the rotated token was bound to the old replication group, which the rebuild destroys, and the new replication group is created with the original `random_password.auth_token.result` plus a fresh secret_version written from the same state value. The previous prose said only "the preserved AUTH token from `random_password.auth_token.result`", which described the random-password value but did not address the Scenario A drift case. Operationally relevant because port migration following an OOB credential rotation (e.g. port restriction in response to a network-exposure finding, applied after rotating credentials) is a plausible incident-response sequence; operators reading the runbook in that posture would otherwise be surprised when their rotated token is silently replaced. The added caveat directs operators who want to carry a token across a port change to run Scenario B (`-replace=random_password.auth_token`) BEFORE the port edit, mirroring the rename guidance.
- **aws-eks-elasticache-redis** (LOW): Propagate the pass-3 N1 port-attribute symmetry fix from `aws_secretsmanager_secret_version.auth.secret_string` to `outputs.tf::port`. The output previously read `var.port`; now it reads `aws_elasticache_replication_group.this.port` so both the consumer-facing output and the secret payload track AWS-authoritative state. Functionally identical today (the resource's port is wired from `var.port` upstream), but the cross-file symmetry eliminates the same future-maintenance trap pass-3 N1 addressed in `secret_string`: a maintainer scanning `outputs.tf` no longer has a cue that `var.*` is a valid alternative source — leaving outputs and the secret payload disagreeing on this would, on a future "consistency" refactor, lose the AWS-authoritative property the secret_string treatment depends on for `host`. Inline comment documents the rationale.

### Fixed (code-review pass 4)

- **aws-eks-elasticache-redis** (HIGH): Correct the `var.port` documentation in `variables.tf` and `resources.tf`, which previously claimed port changes were applied in-place by ElastiCache (the prose was copied verbatim from `aws-eks-aurora-cluster`, where it is true for RDS Aurora's `ModifyDBCluster --port`). AWS does NOT support modifying the port of an ElastiCache replication group: the AWS Terraform provider marks `port` as `ForceNew` on `aws_elasticache_replication_group` (see `terraform-provider-aws/internal/service/elasticache/replication_group.go`), and `aws elasticache modify-replication-group` exposes no `--port` parameter. A `var.port` change therefore destroys the replication group AND its dataset, then creates a fresh one on the new port — operationally equivalent to Scenario C (rebuild). The previous "DELIBERATELY ABSENT" comment block in `resources.tf` and the matching paragraph in `variables.tf` told operators to manually `put-secret-value` the new port into the AUTH secret — but the `replace_triggered_by = [aws_elasticache_replication_group.this.arn]` on `aws_secretsmanager_secret_version.auth` already replaces the secret automatically when the replication group's `.arn` changes (which it does on a ForceNew port edit), and the new secret_version reads the new replication group's host/port plus the preserved AUTH token from `random_password.auth_token.result` (random_password is not replaced, so the AUTH token survives the rebuild). The corrected documentation states the actual behaviour, lists `var.port` change explicitly in the `replace_triggered_by` enumeration, and directs operators to apply Scenario C preconditions (acknowledge dataset loss OR set `final_snapshot_identifier` plus a documented restore plan) rather than the now-obsolete manual-resync runbook. Operationally critical because an operator following the previous runbook would lose every cached key (sessions, OTP state, JWT denylists, rate-limit counters) thinking they were doing a routine port migration.
- **aws-eks-elasticache-redis** (LOW): Tighten the Scenario A out-of-band rotation runbook to use a `NEW_TOKEN` shell variable instead of typing `<new>` in two places (`aws elasticache modify-replication-group --auth-token` and `jq --arg p`). The previous shape silently desynced Redis from the secret if the operator typed different values in the two spots — Redis would accept the modify-replication-group token while the secret stored whatever was passed to `--arg p`, and consumers would then fail auth against Redis with no plan-time signal. Added an inline note explaining the failure mode so future maintainers do not "simplify" the variable back out.
- **aws-eks-elasticache-redis** (LOW): Soften the `subnet_ids` validation error message so it no longer claims to enforce "distinct AZs" — the validation only checks subnet count (the inline comment above already documents that AWS owns the same-AZ-twice failure mode at apply time, since Terraform cannot enumerate subnet AZs without a data lookup). The new wording flags the AZ requirement to operators while accurately scoping what the rule does and does not catch at plan time.
- **examples/aws-eks-elasticache-redis-standalone** (LOW): Switch the standalone example's `vpc_id` / `subnet_ids` / `allowed_security_group_ids` from fake-but-realistic-looking IDs (`vpc-0123456789abcdef0`, `subnet-aaa`, `sg-workload`) to clear `REPLACE_WITH_*` placeholders, matching the multi-az example. A user copy-pasting the standalone example as-is now gets an obvious "you forgot to replace this" failure shape instead of a cryptic "VPC vpc-0123456789abcdef0 does not exist" against AWS minutes into apply.
- **render-service-bundle.sh** (NIT): Drop the dead `else` branch on the portal `db.env` block that handled "APP_SECRET_ARN missing" — the earlier `require_output "$APP_SECRET_ARN" "product_tenant_secret_arns[$PORTAL_TENANT_KEY]" "data"` already exits the script if the ARN is empty, so the inner branch was unreachable. Replaced with a comment documenting the invariant for future maintainers; the two real failure modes (Secrets-Manager read failure and tenant-secret-not-yet-populated) are unchanged.
- **render-service-bundle.sh** (NIT): Surface in CI logs which ACM cert the portal `aws.env` heredoc resolved to. The block already prefers `portal_certificate_arn` and falls back to the shared ingress `certificate_arn` when only the SAN approach is configured, but the choice was previously silent — operators auditing renderer output had to re-run `tofu output` to answer "which cert is portal using?". The new echoes (`ⓘ portal ACM cert: using portal_certificate_arn ...` / `ⓘ ... using certificate_arn (shared ingress cert with portal SAN ...)`) make the decision visible without changing the resolution order.

### Fixed (code-review pass 3)

- **aws-eks-elasticache-redis** (LOW): Add a cross-variable validation on `var.subnet_ids` so `num_cache_clusters >= 2` (which derives Multi-AZ + automatic_failover via `local.ha_enabled`) requires at least two subnets at plan time. Without it, AWS rejects a Multi-AZ replication group whose subnet group does not span at least two AZs minutes into `apply` with a cryptic `InsufficientCacheClusterCapacity` / "subnet group must span multiple AZs" — exactly the failure shape the rest of the module's plan-time validations exist to prevent. Same-AZ-twice still falls through to AWS because we cannot enumerate subnet AZs without a data lookup.
- **aws-eks-elasticache-redis** (NIT): Read `port` off the replication-group resource attribute (`aws_elasticache_replication_group.this.port`) inside `aws_secretsmanager_secret_version.auth`'s `secret_string`, mirroring the existing AWS-authoritative read of `host` from `primary_endpoint_address`. Functionally identical (the resource's port is wired from `var.port` upstream) but eliminates the asymmetry that would otherwise invite a future maintainer to "harmonise" both fields onto `var.*` and lose the AWS-authoritative property of `host`. Inline comment documents the invariant.
- **aws-eks-elasticache-redis** (NIT): Reconcile the two `aws-eks-aurora-cluster` version references on adjacent rules (the for_each-keyed standalone-rule preamble cited `v1.5.6+`; the `depends_on` race comment cited `v1.5.4`) into one preamble that explains both: race observed in v1.5.4 with the prior list-based shape, for_each shape adopted in v1.5.6+. Readers comparing the two rules no longer have to reconcile what looked like a version disagreement.

### Fixed (code-review pass 2)

- **aws-eks-elasticache-redis** (LOW): Tighten the `engine_version` regex from `^7(\.([0-9]+|x))?$` to `^7\.([0-9]+|x)$` so a bare `"7"` is rejected at plan time. AWS ElastiCache requires either a pinned minor (`7.0`, `7.1`, ...) or the `7.x` alias and rejects the major-only form with a cryptic `InvalidParameterValue` minutes into `apply` -- the earlier regex defeated the point of plan-time validation for that one input.
- **aws-eks-elasticache-redis** (LOW): Correct the name-budget comment above the `replication_group_id` length validation in `variables.tf`. The previous comment claimed Secrets Manager secret names "can be 255 / 64+ bytes"; the actual AWS limit is 512 bytes. The 40-byte replication-group budget remains the binding constraint, so the validation logic is unchanged -- only the comment was wrong, and only future maintainers were at risk of being misled.
- **aws-eks-elasticache-redis** (NIT): Add a "submodule invocation note" preamble to the three-scenario rotation runbook in `resources.tf`. The embedded shell snippets reference `terraform output -raw replication_group_id` and `terraform output -raw auth_token_secret_arn`, which resolve against the root module's outputs -- not the submodule's. Consumer stacks invoking this as a submodule (the normal case) must re-export those values at the root before operators can copy-paste the snippets during an incident. The note documents the re-export pattern and a `terraform output -json | jq` alternative.
- **render-service-bundle.sh** (NIT): Wrap the streaming-stack `cd "$STREAMING_DIR"` lookup in an explicit subshell so the working-directory mutation does not leak into the portal/registry blocks below. The earlier form embedded the `cd` in the `if` test clause, which technically worked because every later `read_output` re-establishes its own CWD via its own subshell -- but any future helper that resolved a relative path against `$PWD` would have silently bound against `STREAMING_DIR` after this block ran. Behaviour is unchanged for the existing `ingress` / `structuring` paths.

### Fixed (code-review pass 1)

- **aws-eks-elasticache-redis** (HIGH): Tighten `engine_version` validation to Redis 7.x only (accepting the AWS-native `7.x` alias), and `parameter_group_family` to `redis7` only. The module hardcodes `transit_encryption_mode = "required"` which requires engine 7.0.5+; previously accepting Redis 6.x at plan time would have surfaced as a cryptic `InvalidParameterCombination` error minutes into `apply`.
- **aws-eks-elasticache-redis** (LOW): Tighten `maintenance_window` and `snapshot_window` hour ranges to `00-23` (`([01][0-9]|2[0-3])` instead of the looser `[0-2][0-9]` that accepted up to `29`).
- **aws-eks-elasticache-redis** (LOW): Add missing `description` fields to the `port`, `security_group_id`, and `parameter_group_name` outputs for consistency with the rest of `outputs.tf`.
- **aws-eks-elasticache-redis** (LOW): Add an inline comment on `random_password.auth_token` explaining that the absence of `keepers` is deliberate — rotation is operator-driven via `-replace` so that routine config churn cannot silently regenerate the AUTH token.
- **aws-eks-elasticache-redis** (MEDIUM): Expand the Scenario A runbook in `resources.tf` to document the rename-vs-prior-Scenario-A-rotation interaction. An identifier rename flips the replication group's ARN, replaces the entire AWS resource, and returns both Redis-side and secret-side credentials to the Terraform-state value of `random_password.auth_token.result`. A prior Scenario A rotation is discarded, which is correct because the cluster the rotation applied to no longer exists. Operators who want to carry a specific token across a rename should run Scenario B first to land the value in state, then do the rename.
- **aws-eks-elasticache-redis** (NIT): Sharpen the `depends_on = [aws_security_group.this]` comment on the standalone ingress/egress rules to cite the Aurora module (v1.5.4) precedent explicitly and document that ElastiCache has not been observed to hit the same `InvalidPermission` race; the edge is retained for symmetry and low cost.
- **render-service-bundle.sh** (MEDIUM): Remove the silent hardcoded portal-tenant `DB_NAME` fallback in the portal branch; the earlier `require_output` on `product_tenant_app_role_arns[portal]` already proves the tenant is registered, so a missing entry in `product_tenant_database_names` is a data-stack output-set mismatch that must surface rather than silently pointing portal at a non-existent DB.
- **render-service-bundle.sh** (MEDIUM): Add an inline comment explaining why portal's `db-config.env` sources `host`/`port` from the stack output (`product_cluster_endpoint` / `product_port`) rather than from the portal tenant app secret: the cluster endpoint is AWS-authoritative and survives blue-green cut-overs, and the tenant secret may not exist before the first migrate Job has run.
- **render-service-bundle.sh** (LOW): Add an IRSA-wiring reminder to the portal `aws.env` heredoc noting that attaching the Redis `app_read_policy_arn` to the portal APP IRSA role is the responsibility of the consumer's infrastructure data stack, not this renderer.

### Backward Compatibility

Fully additive. New module, new examples, new operator-tool branch. Existing consumers of `aws-eks-aurora-cluster`, `aws-eks-irsa`, and the other `render-service-bundle.sh` service branches are unaffected.

**Breaking-within-unreleased-scope:** consumers that had already started calling the unreleased `aws-eks-elasticache-redis` module with `engine_version = "6.x"` / `"6.2"` or `parameter_group_family = "redis6.x"` will now fail plan-time validation. No tagged release ships Redis-6.x support, so nothing published is broken.

---

## [1.6.0] — 2026-04-24

### Documentation

- Reconcile CHANGELOG with actual tagged release contents. The previous `[Unreleased] — hotfix/aurora-multi-tenant-secrets` section shipped as `v1.5.9` and is now titled accordingly. The former `[1.5.6]` section described content that was actually tagged as `v1.5.7` (no `v1.5.6` tag exists); its content has been merged into `[1.5.7]`. Sections `[1.5.0]` through `[1.5.4]` have been enriched with module and toolbox changes that were present in the tagged diffs but omitted from the original release notes. The `aws-eks-keycloak` Secrets Manager fallback fix has been moved from `[1.5.0]` (where it was misattributed) to `[1.5.1]` (where it actually shipped).

No Terraform module or example code changes in `v1.6.0`.

---

## [1.5.9] — 2026-04-24

### Features

- **aws-eks-aurora-cluster**: Add optional `tenants` map input for multi-tenant clusters that host per-service logical databases behind a single Aurora cluster. For each tenant, the module provisions:
  - One empty Secrets Manager secret `"<prefix>-<workload>-<tenant>-app-db"`, intentionally not populated by Terraform (the tenant's k8s migrate Job writes the per-service credentials after bootstrapping the Postgres role + logical database).
  - One IAM policy `"...-<tenant>-app-read"` granting `secretsmanager:GetSecretValue` + `secretsmanager:DescribeSecret` on the tenant's app secret only — intended for the tenant's runtime IRSA role. `DescribeSecret` is included so External Secrets Operator and the Secrets Manager CSI driver work without additional wiring.
  - One IAM policy `"...-<tenant>-migrate"` granting master-secret read (`GetSecretValue` + `DescribeSecret`) + tenant-app-secret read+write (`GetSecretValue` + `DescribeSecret` + `PutSecretValue` + `UpdateSecretVersionStage`) — intended for the tenant's migrate-Job IRSA role, explicitly NOT the runtime role. `DescribeSecret` on both secrets is included so migrate Jobs that pull credentials via External Secrets Operator or the Secrets Manager CSI driver work without additional wiring.
- **aws-eks-aurora-cluster**: New outputs `tenant_secret_arns`, `tenant_app_read_policy_arns`, `tenant_migrate_policy_arns`, `tenant_database_names`, `tenant_role_names` (all keyed by tenant name, empty maps when `tenants = {}`). Consumers compose these with `aws-eks-irsa` per-tenant without further boilerplate.
- **aws-eks-aurora-cluster**: Add `tenant_secret_recovery_window_in_days` variable (default 30) to control AWS recovery window for deleted tenant secrets. Set to 0 for immediate deletion in staging environments with frequent tenant churn.
- **aws-eks-aurora-cluster**: Add `master_secret_recovery_window_in_days` variable (default 30) to control AWS recovery window for the cluster master secret. Previously hardcoded to AWS's 30-day default, blocking same-name recreation in staging tear-down/rebuild cycles.
- **aws-eks-aurora-cluster**: The runtime `tenant_app_read` IAM policy now grants both `secretsmanager:GetSecretValue` AND `secretsmanager:DescribeSecret`. `DescribeSecret` is required by External Secrets Operator and the Secrets Manager CSI driver — the previous single-action policy silently broke those integrations.
- **aws-eks-aurora-cluster**: The migrate IAM policy now grants `secretsmanager:GetSecretValue` on the tenant's own app secret (in addition to `DescribeSecret`/`PutSecretValue`/`UpdateSecretVersionStage`). This lets idempotent migrate Jobs short-circuit credential regeneration when the secret is already populated, avoiding password-rotation storms on every re-apply.
- **aws-eks-aurora-cluster**: The migrate IAM policy's `ReadMasterForBootstrap` statement now grants `secretsmanager:DescribeSecret` alongside `secretsmanager:GetSecretValue`. Same rationale as `tenant_app_read`: ESO / Secrets Manager CSI driver issue `DescribeSecret` unconditionally and would silently fail without it. Consistent with the action list the module already applies to tenant app secrets.
- **aws-eks-aurora-cluster**: Add validation for `database_name`, `tenants[*].database_name`, `tenants[*].db_role_name`, and `master_username` to ensure valid unquoted Postgres identifiers (lowercase letters/digits/underscores, starting with letter or underscore). All also validated against the Postgres NAMEDATALEN 63-byte limit.
- **aws-eks-aurora-cluster**: Add validation that resolved `tenants[*].db_role_name` (after applying the hyphen→underscore default derivation) does not equal `var.master_username`. Without this, a tenant key like `postgres` passes plan and the migrate Job fails at run time with `ERROR: role "postgres" already exists` — far from the plan signal. Closes the last naming-collision gap (tenant-vs-tenant and tenant-vs-cluster DB are already guarded).
- **aws-eks-aurora-cluster**: Add TCP port range validation on `var.port` (1-65535). Catches typos at plan time. Note that `var.port` deliberately does NOT auto-sync into the master Secrets Manager secret; see the port-change runbook in `var.port`'s description and the three-scenario runbook in `resources.tf` next to `aws_secretsmanager_secret_version.this`.
- **aws-eks-aurora-cluster**: Add denylist validation on resolved `tenants[*].db_role_name` against Aurora/Postgres reserved role names (`postgres`, `rdsadmin`, `rds_superuser`, `rds_replication`, `rds_iam`, `rds_password`, `public`) and the `pg_*` Postgres-reserved prefix. Catches reserved-role collisions at plan time rather than at migrate-Job `CREATE ROLE` run time. `public` is explicitly included because it is the Postgres implicit pseudo-role and is NOT matched by the `pg_*` prefix check. Complements the pass-10 `db_role_name != master_username` cross-variable check; closes the gap for operators who set a custom `master_username`.
- **aws-eks-aurora-cluster**: Add validation that generated IAM policy names (project_name_prefix + workload_name + tenant + suffix) do not exceed the 128-byte AWS IAM limit. The check uses the longest per-tenant suffix (`-app-read`, 9 bytes) as the worst case — if it fits, `-migrate` (8 bytes) fits too.
- **aws-eks-aurora-cluster**: Add validation that generated RDS identifiers (project_name_prefix + workload_name + suffix) do not exceed the 63-byte AWS RDS identifier limit. The check uses the longest generated suffix `-db-reader-15` (13 bytes, upper bound of `reader_instance_count`); if that fits, cluster/writer/subnet-group/security-group/parameter-group identifiers fit too.
- **aws-eks-aurora-cluster**: Add `lifecycle { ignore_changes = [secret_string], replace_triggered_by = [aws_rds_cluster.this.arn] }` to `aws_secretsmanager_secret_version.this`. `ignore_changes = [secret_string]` lets operators rotate the master password out-of-band (AWS console, psql `ALTER ROLE`, scheduled Lambda) without subsequent applies silently reverting the rotation and breaking every tenant migrate Job (**Scenario A** in the three-scenario runbook inlined next to the resource in `resources.tf`). `replace_triggered_by = [aws_rds_cluster.this.arn]` fires only when the cluster ARN actually changes — i.e. cluster force-replacement: identifier rename via `project_name_prefix`/`workload_name` change, `db_subnet_group_name` recreation, or operator-driven `-replace=aws_rds_cluster.this`. Note that Aurora engine major-version bumps with `allow_major_version_upgrade = true` are in-place via `ModifyDBCluster` and do NOT flip `.arn`; without that flag the provider rejects the plan entirely. On the cases this DOES catch, the secret's `host` is genuinely stale AND `random_password.master_password.result` is freshly written to the new cluster anyway, so rewriting the secret stays consistent with Postgres. The cluster reference is specifically to `.arn` (not the bare resource) so routine in-place cluster updates — backup retention bumps, `deletion_protection` toggles, serverlessv2 scaling edits, tag churn — do NOT trigger replacement and do NOT clobber out-of-band rotations. Terraform-driven password rotation (**Scenario B**) requires temporarily bypassing both this and the cluster's `ignore_changes = [master_password]` and running `-replace=random_password.master_password` alone (data-preserving; no `-replace` of the cluster). Cluster rebuild / disaster recovery (**Scenario C**) is explicitly destructive and documented separately — see the inline runbook.
- **aws-eks-aurora-cluster**: Add `lifecycle { ignore_changes = [master_password] }` to `aws_rds_cluster.this`, symmetric with the `ignore_changes = [secret_string]` on the secret version. Without this, any future regeneration of `random_password.master_password.result` (e.g. length bump, resource replacement) would plan an in-place `master_password` update on the cluster and silently clobber any Postgres-side out-of-band rotation.
- **aws-eks-aurora-cluster**: Add `description` to the cluster master `aws_secretsmanager_secret.this` resource warning against attaching read access to runtime roles. The per-tenant secrets already carried descriptions; this brings the master to parity in the AWS console.
- **aws-eks-aurora-cluster**: Broaden `master_username` output description to reflect that it is useful to any consumer that needs to read the master secret (e.g. Keycloak wiring, per-tenant migrate Jobs), with an explicit "do not expose to runtime workloads" warning.
- **aws-eks-irsa**: Add validation that generated IAM role name (`${project_name_prefix}-irsa-${role_name_suffix}`) does not exceed the 64-byte AWS IAM role name limit. Multi-tenant consumers with long tenant keys would previously fail at apply with a cryptic AWS `ValidationError`; they now fail at plan with an actionable message. Requires Terraform 1.9+ / OpenTofu 1.8+ for the cross-variable reference in the validation block.
- **aws-eks-irsa**: Declare `required_version = ">= 1.9"` in `provider.tf` to enforce the Terraform 1.9 / OpenTofu 1.8 floor required by the cross-variable validation above. Without this declaration, older CLIs emit a cryptic `Variables not allowed` parse error pointed at the validation block rather than an actionable "upgrade your CLI" message.
- **aws-eks-aurora-cluster**: Declare `required_version = ">= 1.9"` in `provider.tf` for the same reason as above — multiple new validation blocks in this MR use cross-variable references (RDS identifier length check spans `project_name_prefix` + `workload_name`; cluster-vs-tenant `database_name` overlap check; tenant-role-vs-`master_username` collision check; per-tenant IAM policy name length check spans `project_name_prefix` + `workload_name` + tenant key). Also used by the `startswith` function in the `pg_*` reserved-prefix denylist (Terraform 1.5+).
- **aws-eks-aurora-cluster**: Default `tenant_role_names` now transform hyphens to underscores so omitted `db_role_name` values produce valid unquoted Postgres identifiers (e.g. tenant key `device-profile` → role name `device_profile`). The derivation lives in `local.resolved_tenant_role_names` in `locals.tf`; the output simply echoes it, and the uniqueness validation duplicates the expression inline because Terraform validation blocks cannot reference locals.
- **aws-eks-aurora-cluster**: New outputs `tenant_secret_recovery_window_in_days` and `master_secret_recovery_window_in_days` echoing the respective input values, for audit/plan visibility.
- **examples/aws-eks-aurora-multi-tenant**: New example showing a shared cluster with two tenants and per-tenant migrate + runtime IRSA wiring.

### Toolbox

- **sync-secure-files.sh**: Minor comment tidy (no behavior change).

### Rationale

Previously, consumers wanting multiple services on one cluster had to hand-roll per-tenant Secrets Manager secrets and the two matching IAM policies per tenant. The path of least resistance — cloning the single-tenant IRSA pattern that granted access to the cluster master secret — gave every tenant's runtime service account read access to that superuser secret, which breaks minimum-necessary and cross-tenant isolation once N>1 services share a cluster. This change moves the multi-tenant machinery into the module so the secure shape is the default shape.

**Note**: This is an additive feature that provides the infrastructure primitives for secure multi-tenant Aurora clusters. Existing consumers with hand-rolled multi-tenant wiring must migrate their consumer-side IRSA bindings to use the new `tenant_app_read_policy_arns` and `tenant_migrate_policy_arns` outputs to realize the security benefits. The module itself does not enforce this migration.

### Backward Compatibility

Fully additive at the resource-creation level. `tenants` defaults to `{}`, in which case no per-tenant Secrets Manager secrets or IAM policies are created.

Existing single-tenant consumers (`journal_db`, `readmodel_db`, `keycloak_db`, etc.) will see the following minor in-place metadata updates on the first apply after upgrade:

- `aws_secretsmanager_secret.this` gains a `description` field (previously unset) → visible `~ description` in-place update, one-time.
- `aws_secretsmanager_secret.this` gains an explicit `recovery_window_in_days = 30` tracking the new `master_secret_recovery_window_in_days` variable. Terraform state will gain the explicit value; no AWS API-side mutation occurs on apply because `recovery_window_in_days` is a `DeleteSecret`-time argument only (AWS does not persist it or return it from `DescribeSecret`, so Terraform cannot reconcile it against AWS state). The value only takes effect on the next `DeleteSecret` for this resource.
- `aws_secretsmanager_secret_version.this` gains a `lifecycle` block (`ignore_changes = [secret_string]` + `replace_triggered_by = [aws_rds_cluster.this.arn]`). Lifecycle blocks themselves don't produce provider-visible diffs, but the first apply will reconcile any existing drift in `secret_string` that Terraform was previously reverting (this is intentional — it stops the revert behavior that was silently breaking out-of-band rotation).
- `aws_rds_cluster.this` gains a `lifecycle { ignore_changes = [master_password] }` block, symmetric with the secret-version treatment above. This prevents future in-place `master_password` updates on the cluster from silently clobbering an out-of-band rotation whenever `random_password.master_password` is regenerated (length bump, resource replacement, etc.). Terraform-driven password rotation (Scenario B in the inline runbook) requires temporarily bypassing both `ignore_changes` blocks and `-replacing` `random_password.master_password` alone — no cluster replacement, no data loss.

### Behavior Changes

- **aws-eks-aurora-cluster**: Added validation requiring `database_name` to be a valid unquoted Postgres identifier (lowercase letters/digits/underscores, starting with letter or underscore). Consumers using uppercase, hyphens, or other characters will fail validation on upgrade.

### Important Operational Notes

**Tenant Removal Ordering**: If you wire IRSA attachments via `for_each` over `tenant_app_read_policy_arns` / `tenant_migrate_policy_arns` outputs (recommended pattern, see `examples/aws-eks-aurora-multi-tenant`), Terraform will automatically sequence attachment destroy → policy destroy in a single apply when you remove a tenant from the `tenants` map.

If you instead use hand-rolled `aws_iam_role_policy_attachment` resources that reference policy ARNs as string literals or data lookups (not via module outputs), you must remove those attachments first, apply, THEN remove the tenant from the map to avoid AWS `DeleteConflict` errors.

**Secret Recovery Window**: Deleted tenant secrets enter a recovery window (default 30 days, configurable via `tenant_secret_recovery_window_in_days`). Re-adding a tenant with the same key within this window will fail with `InvalidRequestException`. For staging environments with frequent tenant churn, set `tenant_secret_recovery_window_in_days = 0` to force immediate deletion.

**Bootstrap Database Naming**: The cluster-level `database_name` must NOT equal any tenant's `database_name`. Tenant migrate Jobs execute `CREATE DATABASE` unconditionally and will fail if the database already exists. Use a dedicated placeholder such as `${workload_name}_bootstrap`.

### Residual Threat Model — Migrate-Job Pod Is a Cluster-Superuser Trust Boundary

The per-tenant `tenant_migrate` policy grants `secretsmanager:GetSecretValue` on the cluster master secret so the migrate Job can bootstrap the per-tenant Postgres role + logical database. This means **a compromised migrate-Job pod for any tenant is equivalent to a compromise of the entire cluster** (and every co-tenant's logical DB). This is a deliberate tradeoff to avoid a bootstrap chicken-and-egg problem, but it shifts rather than eliminates the cross-tenant risk.

Consumers wiring migrate Jobs MUST apply the following controls. These are operational requirements of the module, not optional:

1. **Restricted PodSecurityStandard**: migrate Job namespaces MUST enforce the `restricted` Pod Security Standard (`pod-security.kubernetes.io/enforce: restricted`). This enforces `runAsNonRoot`, `readOnlyRootFilesystem`, dropped capabilities, `seccompProfile: RuntimeDefault`.
2. **Pinned image by digest**: migrate Job `image:` MUST use an immutable `@sha256:...` digest, never a mutable tag.
3. **No shell / debug endpoints**: migrate Job container image MUST NOT ship `sh`, `bash`, `busybox`, or network-debug tooling. Use distroless or minimal base images.
4. **Short-lived Jobs**: migrate Jobs run as Kubernetes `Job` (not `Deployment`) with `backoffLimit <= 3` and `activeDeadlineSeconds`. Complete and terminate — do not keep the pod warm.
5. **Dedicated namespace / ServiceAccount**: the migrate-Job IRSA role must bind to a ServiceAccount used ONLY by the migrate Job, in a namespace hosting NO long-running workloads. NetworkPolicy should restrict egress to AWS Secrets Manager endpoints + the Aurora cluster SG only.
6. **Master-secret rotation after bootstrap**: consider rotating the cluster master password out-of-band after each successful tenant bootstrap. This is an operational runbook, not module behavior. The canonical runbook is inlined as a comment block next to `aws_secretsmanager_secret_version.this` in `terraform/modules/aws-eks-aurora-cluster/resources.tf`; prefer it as the authoritative reference when this CHANGELOG drifts. In summary, the module distinguishes three scenarios:

   - **Scenario A — Out-of-band rotation (no data loss, documented default).** `ALTER USER ... WITH PASSWORD '...'` via psql, then `aws secretsmanager put-secret-value` on the master secret ARN. The module's `ignore_changes = [secret_string]` on the secret version AND `ignore_changes = [master_password]` on the cluster together ensure subsequent `terraform apply` runs do NOT revert this. After rotation, `random_password.master_password.result` in Terraform state is no longer authoritative — that is expected.
   - **Scenario B — Terraform-driven rotation (no data loss, opt-in).** Temporarily comment out both `ignore_changes` blocks, run `terraform apply -replace=random_password.master_password` (prefix module-path if called as a submodule, e.g. `-replace='module.product_db.random_password.master_password'`), then restore the `ignore_changes` blocks. Terraform drives an in-place `ModifyDBCluster` and overwrites the secret version. The cluster itself is NOT replaced.
   - **Scenario C — Cluster rebuild / disaster recovery (DESTRUCTIVE).** `-replace=aws_rds_cluster.this` forces `DeleteDBCluster + CreateDBCluster`, which **destroys every logical database on the cluster, including every tenant's data**. Use only for deliberate rebuilds from backup or staging tear-downs. Preconditions: `deletion_protection = false`, valid `final_snapshot_identifier` (or `skip_final_snapshot = true`), acceptable tenant backups, every tenant migrate Job will re-bootstrap. The destructive command is `terraform apply -replace=random_password.master_password -replace=aws_rds_cluster.this -replace=aws_secretsmanager_secret_version.this` (prefix every address with the module path when called as a submodule).

   `replace_triggered_by = [aws_rds_cluster.this.arn]` on the secret version ensures that cluster force-replacement (identifier rename via `project_name_prefix`/`workload_name` change, `db_subnet_group_name` recreation, or operator-driven `-replace=aws_rds_cluster.this` — the events that legitimately invalidate the secret's `host`) automatically produces a fresh secret version aligned with the new cluster. Aurora engine major-version bumps with `allow_major_version_upgrade = true` are in-place via `ModifyDBCluster` and deliberately do NOT flip `.arn`; the stored `host` remains correct across such upgrades. `.arn` (not the bare resource) is used so routine in-place cluster updates (backup retention, deletion_protection toggle, serverlessv2 scaling, tag churn) do NOT trigger replacement and do NOT clobber a Scenario A rotation. `var.port` edits are NOT wired into the trigger chain by design — any automation rewriting `secret_string` while the cluster stays in place would re-introduce the stale-state-password-overwrites-live-Postgres failure mode that `ignore_changes = [secret_string]` was added to prevent. Operators who change `var.port` must run `aws secretsmanager put-secret-value` manually; the procedure is documented in `var.port`'s description and the inline runbook.

A follow-up module change tracked in `hotfix/aurora-bootstrap-delegate` may introduce a dedicated per-cluster bootstrap role (non-superuser, granted `CREATEROLE`/`CREATEDB` only), which would narrow the migrate-Job blast radius without reintroducing the chicken-and-egg problem.

---

## [1.5.8] — 2026-04-18

### Fixes

- **operator-tools**: Anchor grep pattern in `render-k8s-aws-bundle.sh` to prevent `certificate_arn` matching `api_certificate_arn` when extracting Terraform output values.

---

## [1.5.7] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Replace `count` with `for_each = toset(var.allowed_security_group_ids)` on `aws_vpc_security_group_ingress_rule.allowed`. Resources are now keyed by SG ID instead of list index — deduplicates automatically, eliminates index-shift races on list changes, and makes add/remove surgical. Existing deployments will see a one-time destroy+create cycle on ingress rules (brief connectivity blip, same as v1.5.3 migration). `moved.tf` documents the state-migration path from count-indexed to SG-ID-keyed resources.

> Note: no `v1.5.6` tag was published. The refactor commit references `v1.5.6` in its subject line, but the actual tag cut against this work was `v1.5.7`.

---

## [1.5.5] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Wrap `allowed_security_group_ids` with `distinct()` in the ingress rule `count` and index expressions. Prevents `InvalidPermission.Duplicate` when a caller passes the same SG ID more than once (e.g. when `cluster_security_group_id` and `eks_managed_security_group_id` resolve to the same SG).

---

## [1.5.4] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Add explicit `depends_on = [aws_security_group.this]` to `aws_vpc_security_group_ingress_rule.allowed` and `aws_vpc_security_group_egress_rule.all`. Without this, OpenTofu resolves the SG ID from state (unchanged during the in-place update that removes inline rules) and parallelises standalone rule creation with inline rule revocation, causing `InvalidPermission.Duplicate` errors from the AWS API.

### Toolbox

- **render-k8s-aws-bundle.sh**: Expand service/credential handling (~70 lines added) for improved k8s workload bundle rendering.

---

## [1.5.3] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Replace inline `ingress {}`/`egress {}` blocks in `aws_security_group.this` with standalone `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources. Inline blocks are authoritative and silently remove any standalone rules added by consumers on the same security group. This caused consumer-added standalone rules on the module-managed Aurora SG to be wiped on every apply.

### Migration

On first apply after upgrading from v1.5.2, the plan will show the security group updated in-place (inline rules removed) and new standalone rule resources created. The SG itself is not destroyed/recreated. There is a brief window (seconds) between inline rule removal and standalone rule creation — schedule during low-traffic if possible. See `moved.tf` for details.

### Toolbox

- **render-service-bundle.sh**: Expand service mapping and credential handling (~175 lines added).

---

## [1.5.2] — 2026-04-16

### Breaking Changes (Streaming Example)

- **streaming-full-stack example**: Replace monolithic `confluent` sensitive variable with non-sensitive `confluent_config` + flat `kafka_admin_api_key` / `kafka_admin_api_secret` secret variables. Consumer repos using this pattern must update their variable definitions and module calls.

### Fixes

- **streaming-full-stack example**: Remove all `nonsensitive()` calls from `locals.tf`. Config fields (environment ID, cluster ID, endpoints) are no longer marked sensitive, eliminating `for_each` workarounds.
- **streaming-full-stack example**: Remove `sensitive = true` from `kafka_bootstrap_servers` and `schema_registry_url` outputs — these are non-sensitive connection endpoints.
- **streaming-full-stack example**: Require both `kafka_admin_api_key` and `kafka_admin_api_secret` for credential reconstruction (either both set or both null — no partial credentials).
- **streaming-full-stack example**: Add streaming credentials precondition and fix stale `kafka_rest_endpoint` comment (the Confluent provider appends `/kafka/v3` internally).
- **aws-eks-keycloak**: Guard null `admin_secret_arn` annotation and add admin credentials validation preconditions.
- **aws-eks-keycloak**: Fix hardcoded `db-user` secret lookup and dynamic role grouping in Helm values.
- **aws-eks-aurora-cluster**: Broaden `master_username` output description to reflect general consumer-side usefulness (e.g. Keycloak DB credential wiring, per-tenant migrate-Job usage).

### Documentation

- **streaming-full-stack README**: Replace "Secure Files" section with "Config and Credentials Separation" documenting the committed `terraform.tfvars` + `TF_VAR_*` env var pattern. Remove `.tfvars.example` from tree listing.
- **confluent-bootstrap.sh**: Output `TF_VAR_kafka_admin_api_key` / `TF_VAR_kafka_admin_api_secret` env var lines and `confluent_config` HCL block instead of monolithic `.tfvars` content. Auto-populate `environment_name` from the CLI context.

### Migration

Consumer repos update by:
1. Rename `confluent` variable to `confluent_config` (remove `kafka_admin_credentials` from the object, drop `sensitive = true`)
2. Add `kafka_admin_api_key` and `kafka_admin_api_secret` as flat `string` variables with `sensitive = true`
3. Add `local.kafka_admin_credentials` reconstruction in `locals.tf`
4. Update module calls: `var.confluent.X` → `var.confluent_config.X`, `var.confluent.kafka_admin_credentials` → `local.kafka_admin_credentials`
5. Move config to committed `terraform.tfvars`, secrets to `.env` as `TF_VAR_*` lines
6. Delete secure `.tfvars` files

---

## [1.5.1] — 2026-04-13

### Fixes

- **aws-eks-keycloak**: Resolve DB and admin passwords from Secrets Manager when not explicitly provided. Eliminates ExternalSecretsOperator dependency for first-apply bootstrap — the module reads real credentials at plan time and populates Kubernetes secrets. `ignore_changes` on secret data preserves ESO-managed rotation support.

### Infrastructure

- Bump cicd-pipelines adapter to v0.5.5 and base-containers to v0.5.0.

---

## [1.5.0] — 2026-04-13

### Features

- **aws-eks-keycloak**: Keycloak identity server deployment on EKS via Bitnami Helm chart.
  - Follows `aws-eks-karpenter-controller` / `aws-eks-metrics-server` Helm-on-EKS pattern.
  - DB credentials injected via Secrets Manager ARN from `aws-eks-aurora-cluster` output — never plaintext.
  - Admin credentials via separate Secrets Manager ARN.
  - Optional realm JSON import via ConfigMap (`keycloakConfigCli`).
  - Configurable replicas, resource limits, service type, image tag override.
  - Kubernetes provider required alongside Helm (namespace, secrets, configmap management).
  - Outputs: in-cluster base URL, JWKS URI template, admin console URL, release metadata.
  - `release_name` variable for multi-instance composition (K8s resource names and Helm release name derived from it).
  - `service_port` variable wired into Helm `service.ports.http` and all URL outputs (`base_url`, `jwks_uri_template`, `admin_console_url`). Port suffix appended only when non-80.
  - `extra_helm_values` escape hatch for TLS, ingress, extra env vars, or any chart value not exposed as a module variable.
- **aws-eks-aurora-cluster**: Add `master_username` output for downstream consumers that need the admin username (e.g. Keycloak DB credential wiring).

### Fixes

- **aws-eks-keycloak**: Add `fullnameOverride` to Helm values so Kubernetes resource names match the release name consistently. Remove unused `db-user` secret key that was never referenced by the chart.

### Examples

- **aws-eks-keycloak-with-aurora**: Composed example — `aws-eks-aurora-cluster` (generic preset, `workload_name = "keycloak"`) + `aws-eks-keycloak` wired via module outputs.

---

## [1.4.1]

### Breaking Changes

- **aws-eks-event-journal-db** renamed to **aws-eks-aurora-cluster**. Consumers must update source paths and add `workload_name` and `database_name` (now required, no default).

### Features

- **aws-eks-aurora-cluster**: Generic Aurora PostgreSQL Serverless v2 module replacing the single-purpose `aws-eks-event-journal-db`.
  - `workload_preset` variable with presets: `event-store`, `read-store`, `generic` — matching `cloudflare-website-acceleration` profile pattern.
  - Per-field nullable overrides (`max_connections`, `wal_buffers`, `random_page_cost`, `work_mem`) resolved via nullable ternary (preset value used when override is null).
  - `reader_instance_count` for read replicas (default 0).
  - Always-on audit parameters: `log_connections`, `log_disconnections`.
  - All resource names parameterized via `workload_name` — no hardcoded identifiers.
  - Nullable `security_group_description` and `parameter_group_description` overrides for ForceNew-safe migration.
  - `workload_name` validation tightened to reject consecutive hyphens (e.g. `my--thing`).
  - Output names unchanged for backward compatibility.

### Examples

- **aws-eks-aurora-event-store**: Write-optimized cluster with event-store preset.
- **aws-eks-aurora-read-store**: Read-optimized cluster with reader instance.
- **aws-eks-aurora-generic**: No-preset cluster with individual override.
- **aws-eks-aurora-cqrs-pair**: CQRS composition demonstrating two module calls.

### Migration

Existing consumers update by:
1. Changing source path from `aws-eks-event-journal-db` to `aws-eks-aurora-cluster`
2. Adding `workload_name = "event-journal"`
3. Adding `workload_preset = "event-store"`
4. Adding `database_name = "event_journal"` (previously defaulted)
5. Adding `security_group_description = "Aurora PostgreSQL access for event journal workloads"` (preserves original ForceNew attribute)
6. Adding `parameter_group_description = "Aurora PostgreSQL event journal tuning"` (preserves original ForceNew attribute)

`moved` blocks in the module handle state migration automatically — `tofu plan` will show moves (not destroy/create) for all renamed resources. Steps 5–6 preserve ForceNew attribute values to prevent security group and parameter group recreation. No manual `tofu state mv` or CI changes required.

---

## [1.3.6] — 2026-03-30

### Features

- **aws-eks-nodegroup**: Add optional `kubernetes_version` variable to pin node group Kubernetes version. When `null` (default), inherits cluster version at creation time with no auto-upgrade on subsequent applies.

---

## [1.3.5] — 2026-03-30

### Fixes

- **aws-eks-cluster**: Update default `kubernetes_version` from `1.31` to `1.34`. Kubernetes 1.31 entered EKS Extended Support on November 26, 2025, adding $0.50/hr to the base $0.10/hr control plane cost (~$365/mo surcharge). Version 1.34 is in standard support until December 2, 2026.

---

## [1.3.4] — 2026-03-30

### Fixes

- **aws-eks-cluster**: Tag the EKS-managed cluster security group with `karpenter.sh/discovery` so Karpenter-launched instances receive it via `securityGroupSelectorTerms`. Without this tag, Karpenter nodes only get the Terraform-created additional SG, which lacks the automatic node↔control-plane communication rules, preventing kubelet from registering with the API server.

---

## [1.3.3] — 2026-03-30

### Fixes

- **aws-eks-karpenter-prereqs**: Add `aws_eks_access_entry` (type `EC2_LINUX`) for the Karpenter node role. Without this, kubelet on Karpenter-launched instances cannot authenticate with the EKS API server, so nodes never register with the cluster and Karpenter enters a launch/terminate retry loop.
- **aws-eks-karpenter-prereqs**: Add missing `ec2:DescribeSpotPriceHistory` permission to Karpenter controller policy. Required for spot instance pricing optimization.

---

## [1.3.2] — 2026-03-30

### Fixes

- **aws-eks-karpenter-prereqs**: Add missing IAM instance profile permissions (`iam:*InstanceProfile`) to Karpenter controller policy. Required for Karpenter v1 auto-managed instance profiles per EC2NodeClass. Without these permissions, EC2NodeClasses remain in `Unknown` status and NodePools stay `not ready`, preventing node provisioning.

---

## [1.3.1] — 2026-03-29

### Features

- **aws-eks-karpenter-controller**: Add new module for Karpenter controller deployment on EKS, including service account, controller deployment, and configuration for node provisioning.
- **aws-eks-metrics-server**: Add new module for Metrics Server deployment on EKS, providing essential cluster metrics for HPA and other autoscaling components.
- **HorizontalPodAutoscaler**: Add HPA components for CPU-based pod scaling in workload modules.
- **Karpenter NodePool + EC2NodeClass**: Add components for AWS node provisioning with Karpenter, enabling elastic node-to-node autoscaling.
- **EKS full-stack example**: Update to demonstrate complete scaling patterns combining HPA and Karpenter.

### Fixes

- **operator-tools**: Fix streaming workload service key mapping (ingress/structuring → ingress-server/structuring-server) for proper Kafka credential lookup.
- **operator-tools**: Harden `sync-secure-files.sh` with backup/restore on failure, API call retries, and fail-fast error handling.

### Toolbox

- **render-k8s-aws-bundle.sh**: Add new script for rendering Kubernetes workload bundles with AWS credentials.
- **render-service-bundle.sh**: Enhance with improved service mapping and credential handling.
- **sync-secure-files.sh**: Add robust file synchronization with backup, retry, and recovery mechanisms.

### Documentation

- **operator-tools README**: Update documentation to reflect actual registry behavior and safer replacement flow.

---

## [1.3.0] — 2026-03-27

### Features

- **confluent-streaming-topics**: Add overlay-driven Kafka topic provisioning module. Receives pre-parsed catalog entries and deployment overlays, filters by service/role inclusion and exclusion rules, and creates `confluent_kafka_topic` resources for the active set. Includes `prevent_destroy = true` lifecycle policy for production safety.

### Fixes

- **confluent-streaming-workload-access**: Strip inherited sensitivity from `schema_registry` using `nonsensitive()` so non-secret identifiers (cluster ID, CRN) can be used in `for_each` expressions without inheriting sensitivity from the parent variable.
- **confluent-streaming-workload-access**: Add validation rule for `service_account_display_name` requiring alphanumeric start/end and restricting allowed characters.

### Examples

- **streaming-full-stack**: Add complete consumer implementation example with YAML service catalogs, deployment overlays, region exclusions, stack composition, environment wrappers, Makefile automation, secure file examples, and operator tools reference.
- **streaming-topics-overlay**: Add reference example demonstrating 2 services, 2 roles, one excluded topic, and empty region exclusions.

### Toolbox

- **operator-tools**: Add reusable operator session scripts — `aws-session.sh`, `confluent-session.sh`, `k8s-session.sh` for credential loading and environment setup, and `render-streaming-bundle.sh` for rendering per-workload `.env` credential bundles from Terraform outputs.
- **confluent-bootstrap.sh**: Add idempotent Confluent Cloud bootstrap script for environment, cluster, Schema Registry, admin service account, API keys, and ACL provisioning.

### Documentation

- **README.md**: Add `confluent-streaming-topics` to module inventory and examples list. Add `streaming-full-stack` and operator tools to examples and toolbox sections.
- **Module README**: Document overlay filtering pipeline, topic lifecycle policy, inputs, outputs, usage, and known limitations.
- **operator-tools README**: Document script usage, sourcing patterns, and credential bundle rendering.

---

## [1.2.1] — 2026-03-27

### Infrastructure

- Version bump patch release.

---

## [1.2.0] — 2026-03-26

### Features

- **aws-eks-ci-oidc-access**: Add CI platform OIDC federation to EKS (IAM role, access entry)
- **gcp-gke-ci-oidc-access**: Add CI platform OIDC federation to GKE (Workload Identity, service account)
- **confluent-streaming-workload-access**: Add Confluent workload access module with service accounts, API keys, Kafka ACLs, and optional Schema Registry RBAC

### Examples

- **CI OIDC examples**: Add 6 examples covering GitHub Actions, GitLab CI, and Bitbucket Pipelines for both AWS/EKS and GCP/GKE
- **Confluent examples**: Add examples for commercial Confluent Cloud and external Schema Registry scenarios

### Security Fixes

- **aws-eks-ci-oidc-access**: Fix critical issue where module always created new OIDC provider. Add support for reusing existing providers via `oidc_provider_arn` input. Only one provider per issuer URL is allowed per AWS account.
- **gcp-gke-ci-oidc-access**: Fix Workload Identity IAM binding to use pool-scoped `principalSet` (the only valid GCP format). Provider-level restriction is handled by `attribute_condition` on the provider resource.
- **gcp-gke-ci-oidc-access**: Remove dead `project_name_prefix` input that was unused in resources.
- **aws-eks-ci-oidc-access**: Add validation to require `eks_access_scope_namespaces` when using namespace-scoped access.
- **aws-eks-ci-oidc-access**: Add validation on `oidc_provider_arn` format to fail early on malformed ARNs.
- **aws-eks-ci-oidc-access**: Add validation rejecting duplicate `test`+`claim` combinations in `trust_conditions` to prevent silent value loss from `merge()`.
- **aws-eks-ci-oidc-access**: Guard `oidc_provider_host` local against null `oidc_issuer_url` to surface clear precondition error instead of confusing type error.
- **confluent-streaming-workload-access**: Move `schema_subject_permissions` precondition to always-evaluated resource so permissions passed with `schema_registry = null` are rejected instead of silently ignored.
- **gcp-gke-ci-oidc-access**: Fix `pool_id` and `provider_id` validation to reject trailing hyphens (GCP API requirement).

### Infrastructure

- Replace LICENSE.md with full Apache 2.0 LICENSE file for OSS compliance.

### Documentation

- **README.md**: Update module inventory and examples list with new CI OIDC modules
- **Module READMEs**: Document security improvements and usage patterns for existing vs new providers

---

## [1.1.3] — 2026-03-24

### Infrastructure

- Update base containers reference to `0.4.3` in CI configuration.

---

## [1.1.2] — 2026-03-24

### Fixes

- **aws-eks-event-journal-db**: Set `apply_method = "pending-reboot"` on static parameters (`max_connections`, `wal_buffers`) to prevent `InvalidParameterCombination` errors during apply.

## [1.1.1] — 2026-03-24

### Fixes

- **aws-eks-event-journal-db**: Remove `checkpoint_timeout` from cluster parameter group — Aurora Serverless v2 manages this parameter internally and rejects modifications via the ModifyDBClusterParameterGroup API.

## [1.1.0] — 2026-03-24

### Features

- **aws-eks-event-journal-db**: Add Aurora PostgreSQL Serverless v2 module for event journal workloads running on EKS, including subnet group, security group wiring, parameter group tuning, and Secrets Manager credential publication.
- **aws-eks-secure-s3**: Add hardened S3 module with public-access blocking, encryption, optional lifecycle rules, TLS-only bucket policy, and pre-built readwrite/readonly IAM policies for IRSA consumers.

### Documentation

- **Module inventory**: Document the new AWS data plane modules in `README.md`.

## [1.0.4] — 2026-03-23

### Features

- **Cloudflare module suite**: Add `cloudflare-domain-baseline`, `cloudflare-website-acceleration`, `cloudflare-preview-website`, `cloudflare-access-guard`, `cloudflare-redirect-domain`, and `cloudflare-mail-foundation` for zone posture, public websites, preview publication, Access protection, redirect domains, and mail DNS.
- **Cloudflare examples**: Add reference examples for baseline-only zones, baseline-plus-mail composition, public websites, preview publication, Access protection, redirect domains, and standalone mail DNS publication.

### Fixes

- **cloudflare-domain-baseline**: Split DNS handling so proxyable `A`/`AAAA`/`CNAME` records and non-proxyable `TXT` records are managed separately, and include TXT record IDs in module outputs.
- **cloudflare-domain-baseline**: Tighten IPv4 validation for `A` record values.
- **cloudflare-redirect-domain**: Use a deterministic redirect rule reference derived from `sha256(zone_name)`.

### Documentation

- **Cloudflare module docs**: Clarify baseline-versus-mail composition boundaries, Cloudflare plan requirements for website acceleration, and redirect phase ownership expectations.

## [1.0.0] — 2026-03-17

### Breaking Changes

- Legacy specialized GKE nodepool module deleted. Only `gcp-gke-nodepool` remains.
- **gcp-gke-cluster, gcp-gke-external-nat**: Provider constraint widened from `~> 6.0.0` to `~> 6.0`.
- **aws-eks-cluster**: `vpc_id` and `public_access_cidrs` are required inputs. Removed internal `data "aws_subnet"` lookup.
- **gcp-gke-cluster**: `master_authorized_networks_cidr_blocks` is a required input for control plane access.

### Features

- **gcp-gke-cluster**: Parameterized networking — `subnet_cidr`, `services_cidr`, `pods_cidr`, `master_ipv4_cidr_block`, `ipv6_access_type` with backward-compatible defaults.
- **gcp-gke-cluster**: New outputs — `self_link`, `location`, `endpoint`, `ca_certificate` (sensitive), `service_account_email`.
- **gcp-gke-nodepool** (NEW): Generic single-pool module with labels, taints, kubelet_config, service account, validation. Consumers instantiate N times for multi-pool architectures.
- **aws-eks-vpc** (NEW): Dedicated VPC with public/private subnets, IGW, NAT gateway per AZ, EKS subnet tags. AZ/CIDR length validation.
- **aws-eks-cluster** (NEW): EKS control plane with KMS envelope encryption, OIDC provider for IRSA, CloudWatch logging. Private endpoint by default.
- **aws-eks-nodegroup** (NEW): Generic managed node group with launch template, labels, taints. Consumers instantiate N times.
- **aws-eks-karpenter-prereqs** (NEW): IAM roles, SQS interruption queue, EventBridge rules for Karpenter. No Helm.
- **aws-eks-irsa** (NEW): Generic IRSA role factory for any namespace/service account combination.
- **AWS modules**: `tags` variables for compliance tagging.
- **GCP modules**: `labels` variables where resource labeling is supported.
- Reference examples: `gcp-gke-full-stack`, `aws-eks-full-stack`.

### Fixes

- **aws-eks-cluster**: Removed `data "aws_subnet"` lookup — VPC ID now explicit input.
- **aws-eks-cluster**: Removed `data "tls_certificate"` lookup and `tls` provider dependency. OIDC thumbprint set to `[]` (AWS manages thumbprints for EKS OIDC).
- **gcp-gke-cluster**: Disabled legacy client certificate authentication (`issue_client_certificate = false`).

### Compliance

- Encryption always-on: EKS KMS envelope encryption, EBS gp3 encrypted volumes. No toggles.
- GKE client certificate auth disabled by default.
- Compliance documentation: `docs/security-model.md`, `docs/compliance-notes.md`, `docs/operational-controls.md`.

### Infrastructure

- Initial OSS standardization (LICENSE, NOTICE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, CHANGELOG, ROADMAP)
- Modernize CI/CD: include cicd-pipelines adapter v0.5.0 (gitflow lifecycle, security scanning, publish policy)
- Replace hardcoded module list with auto-discovery loop over terraform/modules/
- Add per-module system detection via naming convention (gcp-*, aws-*/eks-*, cloudflare-*)
