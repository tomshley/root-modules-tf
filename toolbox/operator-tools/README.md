# Operator Tools

Reusable shell scripts for operator session setup, post-apply credential rendering, and GitLab Secure Files sync. Repo-agnostic — every script accepts explicit file paths and TF output names as arguments rather than baking in a layout.

---

## Layout

```
toolbox/operator-tools/
├── aws-session.sh                # source: AWS env + sts get-caller-identity
├── k8s-session.sh                # source: discover EKS + update kubeconfig
├── confluent-session.sh          # source: load Confluent Cloud creds
├── confluent-bootstrap.sh        # one-time Confluent service-account + key bootstrap
├── render-streaming-bundle.sh    # render per-workload Kafka/SR .env files
├── render-ci-deploy-bundle.sh    # render CI deploy .env from cloud stack
├── render-bundle.sh              # render a single credential bundle (subcommand-based)
├── sync-secure-files.sh          # upload .secure_files/ to GitLab Secure Files
├── capture-dns-snapshot.sh       # capture byte-stable DNS snapshot from BIND zone exports
├── compare-dns-snapshots.sh      # diff two snapshots; gate apply on stability
├── verify-dns-1to1.sh            # semantic 1:1 verify of live DNS vs. BIND exports
├── lib/
│   └── render-helpers.sh         # sourceable bash library (low-level)
└── README.md
```

---

## Sessions and one-shot helpers

### `aws-session.sh` *(source)*

```bash
source /path/to/operator-tools/aws-session.sh /path/to/.secure_files/staging-us-east-1-cloud.env
```

Loads AWS credentials from an env file (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` / `AWS_REGION`), unsets `AWS_PROFILE`/`AWS_SESSION_TOKEN` so static credentials take effect, and verifies via `aws sts get-caller-identity`.

### `confluent-session.sh` *(source)*

```bash
source /path/to/operator-tools/confluent-session.sh /path/to/.secure_files/staging-us-east-1-streaming.env
```

Loads Confluent Cloud credentials (`CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET`) and optionally verifies with the `confluent` CLI.

### `k8s-session.sh` *(source)*

Auto-discovers the EKS cluster and updates kubeconfig. Requires AWS session loaded first.

```bash
source /path/to/operator-tools/aws-session.sh .secure_files/staging-us-east-1-cloud.env
source /path/to/operator-tools/k8s-session.sh
```

### `confluent-bootstrap.sh`

One-time script that creates the Confluent Cloud service accounts, API keys, and ACLs Terraform needs. Operator's personal Confluent Cloud login is used; once bootstrap is done, Terraform authenticates with the created service-account keys.

```bash
./confluent-bootstrap.sh \
  --environment   env-XXXXX \
  --cluster       lkc-XXXXX \
  --tf-sa-name    tf-my-infrastructure \
  --admin-sa-name my-staging-kafka-admin \
  --output-dir    /path/to/.secure_files
```

Idempotent. Outputs values for `.env` / `.tfvars` files; if `--output-dir` is given, writes `bootstrap-output.env` (chmod 600).

### `render-streaming-bundle.sh`

Renders per-workload Kafka + SR + Flink credential `.env` files from a streaming-stack's outputs. Workload set is data-driven — discovered from the union of the `workload_kafka_api_key_ids` and `workload_flink_api_key_ids` map outputs, so a stack with only Kafka workloads, only a Flink deploy SA, or both will produce the correct per-workload bundle set automatically.

```bash
./render-streaming-bundle.sh /path/to/environments/staging/us-east-1/streaming
```

Each `<stack-dir>/.env-bundle/<workload>.env` file (chmod 600) is composed of up to three blocks in this order:

- **Kafka**: `KAFKA_BOOTSTRAP_SERVERS`, `KAFKA_API_KEY`, `KAFKA_API_SECRET` — when the workload has a Kafka API key in `workload_kafka_api_key_ids`.
- **Schema Registry**: `SCHEMA_REGISTRY_URL`, `SCHEMA_REGISTRY_API_KEY`, `SCHEMA_REGISTRY_API_SECRET` — when SR is configured at the cluster level and the workload has an SR API key.
- **Flink (Confluent Cloud)**: `FLINK_PLATFORM`, `FLINK_REST_ENDPOINT`, `FLINK_COMPUTE_POOL_ID`, `FLINK_RUNNER_SERVICE_ACCOUNT_ID`, `FLINK_ENVIRONMENT_ID`, `FLINK_API_KEY`, `FLINK_API_SECRET` — when the workload has a Flink API key in `workload_flink_api_key_ids`. Plus `FLINK_ORGANIZATION_ID` and `FLINK_STATEMENTS_PATH` (a pre-rendered Flink Gateway path tail of the form `/sql/v1/organizations/<org>/environments/<env>/statements`) when the stack additionally exposes a `flink_organization_id` output. `FLINK_PLATFORM=confluent_cloud` is a discriminator the consumer's submit script switches on to pick the right request-body shape; pre-rendering the path lets a `curl` + Basic-auth consumer reach the statements collection without a vendor CLI or a runtime URL builder.

A workload with only a Flink key renders a Flink-only file (no empty `KAFKA_*`/`SCHEMA_REGISTRY_*` lines). A workload with no credentials in any of the three maps is skipped with a log line.

### `render-ci-deploy-bundle.sh`

Renders the CI OIDC deploy bundle (cluster name, region, role) from a cloud-stack's outputs.

```bash
./render-ci-deploy-bundle.sh /path/to/cloud-stack my-app-staging
```

Output: `<stack-dir>/.env-bundle/ci-deploy.env`, chmod 600.

### `sync-secure-files.sh`

Uploads `.secure_files/` to a GitLab project's Secure Files store with backup/restore on failure.

```bash
./sync-secure-files.sh --project-id 76128095 --token "$GITLAB_TOKEN"
```

---

## DNS migration tools

A three-script chain used to build a rollback-evidence baseline when migrating authoritative DNS records from a dashboard/manual configuration into Terraform-managed state. The chain is intentionally `dig` + `awk` + `diff` only — no provider credentials, no TF state — so it produces evidence independent of the migration tooling itself.

The input to all three is a directory of BIND-format zone exports (one `<zone>.txt` per zone) — the format Cloudflare's dashboard "Export DNS records" button produces.

### `capture-dns-snapshot.sh`

Writes a deterministic, byte-stable snapshot of every authoritative DNS record in the export directory by querying `dig +short @$NAMESERVER` per (fqdn, type) pair, plus a synthesized AAAA + NS probe per zone apex. Output is sorted and locale-pinned (`LC_ALL=C`) so two snapshots from the same DNS state produce identical files regardless of operator machine locale.

```bash
NAMESERVER=ns1.cloudflare.com \
  ./capture-dns-snapshot.sh ./zone-exports/ ./snapshots/pre-plan.txt
```

Capture three times in a typical migration: pre-plan (the rollback baseline), pre-apply (proves nobody mutated DNS during the planning window), post-apply (proves apply was a wire-level no-op).

### `compare-dns-snapshots.sh`

Diffs two snapshots, stripping the header timestamp lines so capture time does not produce false drift.

```bash
./compare-dns-snapshots.sh ./snapshots/pre-plan.txt ./snapshots/pre-apply.txt
```

Exit 0 = snapshots are 1:1 identical. Exit 1 = drift detected (output is standard `diff(1)` format so failing records are visible). Exit 2 = invocation error.

### `verify-dns-1to1.sh`

Semantic per-RRset verification. Every `(fqdn, type)` RRset described in the BIND export is compared **set-equal** against the live answer; both *missing* values (in BIND, absent from live) and *extra* values (in live, absent from BIND) are reported as drift via `comm`. The extra-value detection is the operationally critical half — it catches a record that was left behind by a previous DNS provider, or hand-added during the migration window, and never made it into the export. A per-line / per-record check would silently miss those.

```bash
NAMESERVER=ns1.cloudflare.com \
  ./verify-dns-1to1.sh ./zone-exports/
```

Output on a clean run:

```
  ✓ MX example.com (3 value(s))
  ✓ A api.example.com (2 value(s))
  ✓ PROXIED A example.com (alive, 1 BIND record(s))
```

Output on drift:

```
  ✗ MX example.com DRIFT
    Missing (declared in BIND, absent from live):
      - 10 mx1.example-mail.com
    Extra (present in live, absent from BIND):
      + 20 mx1.legacy-provider.com
```

Proxied RRsets (any record with `; cf-proxied:true`) take a separate path: live must be non-empty, but byte-equality is not enforced because Cloudflare returns its anycast addresses, not the origin values. SOA and apex NS are skipped — both are managed at the registrar/parent-zone level; `capture-dns-snapshot.sh` covers them in the byte-stable snapshot path.

Exit 0 = every RRset 1:1 + every proxied RRset alive. Exit 1 = any drift or any proxied RRset not resolving. Pairs with the snapshot tools: the snapshot pair answers "did anything change?", this answers "is the live state actually what the export said?".

**Bound:** the BIND export is the source-of-truth. The tool catches every divergence within RRsets the export describes, but cannot enumerate live records whose `(fqdn, type)` is absent from the export entirely (public DNS does not support enumerate-zone over `dig`). The export must therefore be a complete dump of the zone — for Cloudflare, the dashboard's "Export DNS records" button produces that.

---

## `render-bundle.sh` — single-bundle command-line renderer

`render-bundle.sh` is a subcommand-based command-line tool. It knows the *shape* of every credential bundle that root-modules-tf modules typically produce; the customer passes the *data* (which TF stack, which output names, which secret ARN, which tenant key). Each bundle invocation writes one chmod-600 `.env` (or `.pem`) at a path the customer chooses.

```bash
./render-bundle.sh --list
./render-bundle.sh <bundle> --help
./render-bundle.sh <bundle> [flags...]
```

### Available bundles

Each bundle maps 1:1 to a root-modules-tf module's outputs. Run `--list` to see them.

| Bundle | Anchored to | Produces |
|---|---|---|
| `ci-deploy` | `aws-eks-cluster` + `aws-eks-ci-oidc-access` | CI deploy `.env` (cluster, region, role, namespace) |
| `aurora-config` | `aws-eks-aurora-cluster` | Aurora connection `.env` (host, port, database) |
| `aurora-master` | `aws-eks-aurora-cluster` | Aurora creds from cluster master secret |
| `aurora-tenant` | `aws-eks-aurora-cluster` | Aurora creds from a tenant secret (multi-tenant pattern) |
| `redis-config` | `aws-eks-elasticache-redis` | Redis connection metadata (AUTH stays in Secrets Manager) |
| `keycloak` | `aws-eks-keycloak` | Cluster-internal JWKS / issuer / token URLs |
| `s3-config` | `aws-eks-secure-s3` | Bucket name + region |
| `kafka-workload` | `confluent-streaming-workload-access` | Per-workload Kafka + SR credentials |
| `rds-ca-pair` | (Amazon RDS bundle) | RDS root CA PEM + pointer `.env` |
| `aws-arns` | (generic) | Project N TF outputs from N stacks into a single `.env` |
| `registry` | (Tomshley CI convention) | GitLab container registry creds from `.credentials.gitlab` |

Each bundle defaults its TF output keys to the names the matching root-modules-tf module ships. Override per-bundle via flags like `--cluster-output`, `--host-output`, `--secret-arn-output` if your stack renames them.

### Examples

CI deploy bundle from a cloud stack:

```bash
./render-bundle.sh ci-deploy \
  --out /tmp/secure/staging-k8s-deploy.env \
  --cloud-dir environments/staging/us-east-1/cloud \
  --region us-east-1 \
  --namespace my-app-staging
```

Aurora master credentials, fetching the secret ARN from a TF output:

```bash
./render-bundle.sh aurora-master \
  --out /tmp/secure/staging-k8s-db.env \
  --region us-east-1 \
  --secret-arn-output aurora_master_secret_arn \
  --data-dir environments/staging/us-east-1/data
```

Multi-stack ARN projection (the most flexible bundle — pass any keys + outputs you want):

```bash
./render-bundle.sh aws-arns \
  --out /tmp/secure/staging-k8s-aws.env \
  --stack tls=environments/staging/us-east-1/tls \
  --stack data=environments/staging/us-east-1/data \
  --stack cloud=environments/staging/us-east-1/cloud \
  --emit ACM_CERT_ARN=tls:certificate_arn \
  --emit IRSA_ROLE_ARN=data:my_service_irsa_role_arn \
  --emit KARPENTER_NODE_ROLE=cloud:karpenter_node_role_name
```

Multi-tenant Aurora secret with map[key] lookup:

```bash
./render-bundle.sh aurora-tenant \
  --out /tmp/secure/staging-k8s-db.env \
  --region us-east-1 \
  --secret-arn-output 'tenant_secret_arns[my-tenant]' \
  --data-dir environments/staging/us-east-1/data
```

Cert resolution with fallback (prefer dedicated cert, fall back to shared):

```bash
./render-bundle.sh aws-arns \
  --out /tmp/secure/staging-k8s-aws.env \
  --stack tls=environments/staging/us-east-1/tls \
  --emit ACM_CERT_ARN=tls:portal_certificate_arn \
  --emit-fallback ACM_CERT_ARN=tls:certificate_arn
```

### Per-service composition (the "right way")

Render multiple bundles for a single service by sequencing `render-bundle.sh` calls in a small per-service shell script. The customer's per-service file is *declarative* — TF output names + tenant keys + namespaces, no rendering logic. Skeleton:

```bash
#!/usr/bin/env bash
# my-service.sh — render every bundle my-service needs
set -euo pipefail

# Adjust the path to wherever you've checked out root-modules-tf
# (e.g. a git submodule under vendor/, a relative sibling repo, etc).
OPERATOR_TOOLS=/path/to/root-modules-tf/toolbox/operator-tools
RENDER_BUNDLE="$OPERATOR_TOOLS/render-bundle.sh"

INFRA_DIR=$1
TARGET_DIR=$2
ENV=staging
REGION=us-east-1
SECURE_DIR="$TARGET_DIR/.secure_files"
PREFIX="$ENV-k8s"
NS="my-platform-my-service-$ENV"

CLOUD_DIR="$INFRA_DIR/environments/$ENV/$REGION/cloud"
DATA_DIR="$INFRA_DIR/environments/$ENV/$REGION/data"
TLS_DIR="$INFRA_DIR/environments/$ENV/$REGION/tls"
STREAMING_DIR="$INFRA_DIR/environments/$ENV/$REGION/streaming"

"$RENDER_BUNDLE" ci-deploy \
  --out "$SECURE_DIR/$PREFIX-deploy.env" \
  --cloud-dir "$CLOUD_DIR" --region "$REGION" --namespace "$NS"

"$RENDER_BUNDLE" aws-arns \
  --out "$SECURE_DIR/$PREFIX-aws.env" \
  --stack tls="$TLS_DIR" --stack data="$DATA_DIR" --stack cloud="$CLOUD_DIR" \
  --emit ACM_CERT_ARN=tls:certificate_arn \
  --emit IRSA_ROLE_ARN=data:my_service_irsa_role_arn \
  --emit KARPENTER_NODE_ROLE=cloud:karpenter_node_role_name

"$RENDER_BUNDLE" aurora-config \
  --out "$SECURE_DIR/$PREFIX-db-config.env" \
  --data-dir "$DATA_DIR" \
  --host-output aurora_cluster_endpoint --port-output aurora_port

"$RENDER_BUNDLE" aurora-master \
  --out "$SECURE_DIR/$PREFIX-db.env" --region "$REGION" \
  --secret-arn-output aurora_master_secret_arn --data-dir "$DATA_DIR"

"$RENDER_BUNDLE" rds-ca-pair --secure-dir "$SECURE_DIR" --prefix "$PREFIX"

"$RENDER_BUNDLE" registry \
  --out "$SECURE_DIR/$PREFIX-registry.env" --secure-dir "$SECURE_DIR"
```

That's the entire customer-side render flow for a typical service. To add another service, copy the file and edit which bundles + which TF output names. To add a new bundle to an existing service, add one `"$RENDER_BUNDLE" <name>` line.

---

## Cookbook: mixing OSS bundles with custom (non-root-modules-tf) bundle shapes

If your service needs a bundle shape that isn't on the OSS list — say, a Vault token, a Doppler secret pull, an in-house rotation pattern — write your own renderer alongside the OSS calls. Use `lib/render-helpers.sh` for the lower-level mechanics (TF output reads, Secrets Manager reads, chmod-600 file writes).

```bash
#!/usr/bin/env bash
set -euo pipefail

OPERATOR_TOOLS=/path/to/root-modules-tf/toolbox/operator-tools
RENDER_BUNDLE="$OPERATOR_TOOLS/render-bundle.sh"
# shellcheck disable=SC1091
source "$OPERATOR_TOOLS/lib/render-helpers.sh"

# 1. Standard OSS bundles for the standard shapes
"$RENDER_BUNDLE" ci-deploy --out "$OUT/deploy.env" --cloud-dir "$CLOUD_DIR" \
  --region "$REGION" --namespace "$NS"

"$RENDER_BUNDLE" aws-arns --out "$OUT/aws.env" \
  --stack data="$DATA_DIR" \
  --emit IRSA_ROLE_ARN=data:my_irsa_role_arn

# 2. Custom: read a Vault token via your own helper
init_render_counters
VAULT_TOKEN=$(get_secret_field "$VAULT_SECRET_ARN" "$REGION" token)
if [[ -n "$VAULT_TOKEN" ]]; then
  write_file_secure "$OUT/vault.env" 600 <<EOF
VAULT_TOKEN=$VAULT_TOKEN
EOF
  emit_ok "$OUT/vault.env"
else
  emit_skip "vault.env (token not yet seeded)"
fi
print_render_summary
```

The boundary is: OSS bundles cover the modules in this repo. Anything outside that — Vault, Doppler, your private rotation tool, your private DB instead of Aurora — is your renderer, calling into `lib/render-helpers.sh` for the plumbing.

---

## `lib/render-helpers.sh` — sourceable low-level library

`render-bundle.sh` is built on top of this library. Source it directly if you're writing a custom renderer (see Cookbook above) and don't want to spawn a subprocess per file.

| Category | Functions |
|---|---|
| Counters & logging | `init_render_counters`, `emit_ok FILE`, `emit_skip MSG`, `emit_info MSG`, `print_render_summary` |
| Validation | `require_command CMD...`, `require_directory DIR [LABEL]`, `require_env_var VAR [LABEL]` |
| TF outputs | `read_tf_output DIR KEY`, `read_tf_output_required DIR KEY [LABEL]`, `read_tf_output_json DIR KEY`, `read_tf_output_map_value DIR KEY MAP_KEY` |
| Secrets Manager | `get_secret_string ARN REGION`, `get_secret_field ARN REGION FIELD` |
| File writers | `write_file_secure PATH MODE` (reads stdin), `download_rds_ca_bundle OUTFILE [URL]` |

Set `TOFU=terraform` to use Terraform instead of OpenTofu. Bash 3.2+ compatible (macOS default).

---

## Consumer Usage

### Workspace-local invocation

```bash
TOOLS=/path/to/root-modules-tf/toolbox/operator-tools

source "$TOOLS/aws-session.sh" .secure_files/staging-us-east-1-cloud.env
source "$TOOLS/k8s-session.sh"

"$TOOLS/render-bundle.sh" ci-deploy --out ... --cloud-dir ... --region us-east-1 --namespace ...
```

### Release artifact (future)

```bash
curl -sL https://github.com/tomshley/root-modules-tf/releases/download/vX.Y.Z/operator-tools.tar.gz | tar xz
operator-tools/render-bundle.sh --list
```

---

## Future expansion

Terraform-based credential fetchers can be added as subdirectories that use `tofu apply` with local-only state (`.gitignore`d) to fetch short-lived credentials from external secret stores. The state file is ephemeral — it captures no real infrastructure.

```
toolbox/operator-tools/
├── ... (existing)
├── vault-credentials/
│   └── main.tf
└── delinia-credentials/
    └── main.tf
```
