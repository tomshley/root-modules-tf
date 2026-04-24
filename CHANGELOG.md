# Changelog

All notable changes to this project are documented in this file.

This project follows Semantic Versioning.

---

## [Unreleased] — hotfix/aurora-multi-tenant-secrets

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

- **operator-tools**: Anchor grep pattern in `aws-bundle helper` to prevent `certificate_arn` matching `api_certificate_arn` when extracting Terraform output values.

---

## [1.5.7] — 2026-04-17

### Infrastructure

- Version bump patch release (no functional changes).

---

## [1.5.6] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Replace `count` with `for_each = toset(var.allowed_security_group_ids)` on `aws_vpc_security_group_ingress_rule.allowed`. Resources are now keyed by SG ID instead of list index — deduplicates automatically, eliminates index-shift races on list changes, and makes add/remove surgical. Existing deployments will see a one-time destroy+create cycle on ingress rules (brief connectivity blip, same as v1.5.3 migration).

---

## [1.5.5] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Wrap `allowed_security_group_ids` with `distinct()` in the ingress rule `count` and index expressions. Prevents `InvalidPermission.Duplicate` when a caller passes the same SG ID more than once (e.g. when `cluster_security_group_id` and `eks_managed_security_group_id` resolve to the same SG).

---

## [1.5.4] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Add explicit `depends_on = [aws_security_group.this]` to `aws_vpc_security_group_ingress_rule.allowed` and `aws_vpc_security_group_egress_rule.all`. Without this, OpenTofu resolves the SG ID from state (unchanged during the in-place update that removes inline rules) and parallelises standalone rule creation with inline rule revocation, causing `InvalidPermission.Duplicate` errors from the AWS API.

---

## [1.5.3] — 2026-04-17

### Fixes

- **aws-eks-aurora-cluster**: Replace inline `ingress {}`/`egress {}` blocks in `aws_security_group.this` with standalone `aws_vpc_security_group_ingress_rule` and `aws_vpc_security_group_egress_rule` resources. Inline blocks are authoritative and silently remove any standalone rules added by consumers on the same security group. This caused consumer-added standalone rules on the module-managed Aurora SG to be wiped on every apply.

### Migration

On first apply after upgrading from v1.5.2, the plan will show the security group updated in-place (inline rules removed) and new standalone rule resources created. The SG itself is not destroyed/recreated. There is a brief window (seconds) between inline rule removal and standalone rule creation — schedule during low-traffic if possible. See `moved.tf` for details.

---

## [1.5.2] — 2026-04-16

### Breaking Changes (Example Only — No Module Changes)

- **streaming-full-stack example**: Replace monolithic `confluent` sensitive variable with non-sensitive `confluent_config` + flat `kafka_admin_api_key` / `kafka_admin_api_secret` secret variables. Consumer repos using this pattern must update their variable definitions and module calls.

### Fixes

- **streaming-full-stack example**: Remove all `nonsensitive()` calls from `locals.tf`. Config fields (environment ID, cluster ID, endpoints) are no longer marked sensitive, eliminating `for_each` workarounds.
- **streaming-full-stack example**: Remove `sensitive = true` from `kafka_bootstrap_servers` and `schema_registry_url` outputs — these are non-sensitive connection endpoints.

### Documentation

- **streaming-full-stack README**: Replace "Secure Files" section with "Config and Credentials Separation" documenting the committed `terraform.tfvars` + `TF_VAR_*` env var pattern. Remove `.tfvars.example` from tree listing.
- **confluent-bootstrap.sh**: Output `TF_VAR_kafka_admin_api_key` / `TF_VAR_kafka_admin_api_secret` env var lines and `confluent_config` HCL block instead of monolithic `.tfvars` content.

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
- **aws-eks-keycloak**: Resolve DB and admin passwords from Secrets Manager when not explicitly provided. Eliminates ExternalSecretsOperator dependency for first-apply bootstrap — the module reads real credentials at plan time and populates Kubernetes secrets. `ignore_changes` on secret data preserves ESO-managed rotation support.

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

- **aws-bundle helper**: Add new script for rendering Kubernetes workload bundles with AWS credentials.
- **service-bundle helper**: Enhance with improved service mapping and credential handling.
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
