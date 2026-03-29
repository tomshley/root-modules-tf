# Operator Tools

Reusable shell scripts for operator session setup and post-apply credential rendering.

These tools are **repo-agnostic** — they accept explicit file paths as arguments rather than deriving paths from a repository root. Consumer infrastructure repos invoke them via workspace-local relative paths or by downloading a release artifact.

---

## Scripts

### `aws-session.sh`

Source this to load AWS credentials from an env file and verify connectivity.

```bash
source /path/to/operator-tools/aws-session.sh /path/to/.secure_files/staging-us-east-1-cloud.env
```

**Expects in env file:** `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` (or `AWS_REGION`).

**Actions:** Sources the env file, unsets `AWS_PROFILE` and `AWS_SESSION_TOKEN` so static credentials take effect, then runs `aws sts get-caller-identity` to verify.

### `confluent-session.sh`

Source this to load Confluent Cloud credentials from an env file and verify connectivity.

```bash
source /path/to/operator-tools/confluent-session.sh /path/to/.secure_files/staging-us-east-1-streaming.env
```

**Expects in env file:** `CONFLUENT_CLOUD_API_KEY`, `CONFLUENT_CLOUD_API_SECRET`.

**Actions:** Parses the env file for Confluent credentials (handles quoted values), exports them, and optionally verifies with the `confluent` CLI if installed.

### `k8s-session.sh`

Source this to auto-discover the EKS cluster and update kubeconfig.

```bash
# Requires AWS credentials to be loaded first
source /path/to/operator-tools/aws-session.sh /path/to/.secure_files/staging-us-east-1-cloud.env
source /path/to/operator-tools/k8s-session.sh
```

**Requires:** `AWS_REGION` must be set (via `aws-session.sh` or manually).

**Actions:** Lists EKS clusters in the region, picks the first, runs `aws eks update-kubeconfig`, and verifies with `kubectl cluster-info`.

### `render-streaming-bundle.sh`

Run this after a streaming stack apply to render per-workload credential `.env` files.

```bash
./render-streaming-bundle.sh /path/to/environments/staging/us-east-1/streaming
```

**Requires:** `tofu` (or set `TOFU=terraform`), `jq`. The stack directory must have been initialized and applied.

**Output:** Creates `<stack-dir>/.env-bundle/<workload>.env` for each workload with Kafka and Schema Registry credentials. All files are `chmod 600`.

### `confluent-bootstrap.sh`

One-time bootstrap script that creates the Confluent Cloud service accounts, API keys, and ACLs that Terraform needs to manage a streaming stack. Uses the operator's personal Confluent Cloud login — once bootstrap is complete, Terraform authenticates with the created service account keys.

```bash
./confluent-bootstrap.sh \
  --environment  env-XXXXX \
  --cluster      lkc-XXXXX \
  --tf-sa-name   tf-my-infrastructure \
  --admin-sa-name my-staging-kafka-admin \
  --output-dir   /path/to/.secure_files
```

**Requires:** `confluent` CLI (v3+), `jq`, `curl`. The operator must have a Confluent Cloud user account with permissions to create service accounts and API keys.

**Arguments:**

| Flag | Required | Description |
|---|---|---|
| `--environment` | Yes | Confluent Cloud environment ID (`env-XXXXX`) |
| `--cluster` | Yes | Kafka cluster ID (`lkc-XXXXX`) |
| `--tf-sa-name` | Yes | Name for the Terraform provider service account |
| `--admin-sa-name` | Yes | Name for the Kafka admin service account |
| `--output-dir` | No | Directory to write `bootstrap-output.env` with all values |

**Creates:**

1. **Terraform provider service account** + EnvironmentAdmin role binding + **Cloud API key** (for `.env`)
2. **Kafka admin service account** + **Cluster API key** + cluster admin ACLs — topic CRUD, consumer-group CRUD, and ALTER on cluster-scope for ACL creation (for `.tfvars`)
3. Retrieves **Schema Registry CRN** (not visible in the Confluent Cloud UI)
4. Retrieves **Kafka bootstrap servers** and **REST endpoint**
5. Verifies the Cloud API key with the Confluent Cloud REST API

**Output:** Prints all values needed for the `.env` and `.tfvars` files. If `--output-dir` is specified, writes a `bootstrap-output.env` file (`chmod 600`) with all values in parseable `KEY=value` format.

**Idempotent:** If the service accounts already exist, they are reused. New API keys are always created (old keys are not deleted — revoke them manually if replacing).

---

### `render-ci-deploy-bundle.sh`

Renders a CI deploy credential bundle from cloud stack Terraform outputs. The output file contains the OIDC role ARN, cluster name, and region needed by consumer CI pipelines to authenticate via GitLab OIDC → AWS IAM role.

Reads outputs via `make output` (Makefile wrapper convention), falling back to raw `tofu output` if no Makefile is present.

```bash
./render-ci-deploy-bundle.sh [stack-dir] [namespace]
```

**Requires:** `tofu` (or set `TOFU=terraform`), `make`.

**Arguments:**

| Argument | Required | Description |
|---|---|---|
| `stack-dir` | No (default: `pwd`) | Path to the cloud stack directory with Terraform state |
| `namespace` | No | Kubernetes namespace to include in the output file |

**Output:** `<stack-dir>/.env-bundle/ci-deploy.env` (`chmod 600`) with:

- `AWS_DEFAULT_REGION` / `AWS_REGION`
- `K8S_CLUSTER_NAME`
- `CI_DEPLOY_ROLE_ARN`
- `K8S_NAMESPACE` (when provided)

The rendered file is intended to be copied to consumer project `.secure_files/` directories and uploaded to GitLab Secure Files as `staging-k8s-deploy.env`. Pass the target namespace as the second argument to include `K8S_NAMESPACE` automatically.

**Prerequisite:** The cloud stack must have been applied with `ci_oidc_access` configured. If `ci_deploy_role_arn` is not in the Terraform outputs, the script exits with an error.

### `render-k8s-aws-bundle.sh`

Renders per-service AWS resource `.env` files from Terraform outputs across multiple stacks (cloud, data, tls). The output file contains the exact variable names expected by CI deploy job `sed` placeholder substitution.

Reads outputs via `make output` (Makefile wrapper convention), falling back to raw `tofu output` if no Makefile is present.

```bash
./render-k8s-aws-bundle.sh --service ingress \
  --cloud-dir /path/to/environments/staging/us-east-1/cloud \
  --data-dir  /path/to/environments/staging/us-east-1/data \
  --tls-dir   /path/to/environments/staging/us-east-1/tls
```

**Requires:** `tofu` (or set `TOFU=terraform`), `make`.

**Arguments:**

| Flag | Required | Description |
|---|---|---|
| `--service` | Yes | One of: `ingress`, `structuring` |
| `--cloud-dir` | Yes | Path to the cloud stack directory (`karpenter_node_role_name`) |
| `--data-dir` | Yes | Path to the data stack directory (`ingress_irsa_role_arn` or `structuring_irsa_role_arn`) |
| `--tls-dir` | ingress only | Path to the tls stack directory (`certificate_arn`) |

**Output:** `<cloud-dir>/.env-bundle/<service>-k8s-aws.env` (`chmod 600`) with:

- **ingress**: `ACM_CERT_ARN`, `IRSA_ROLE_ARN`, `KARPENTER_NODE_ROLE`
- **structuring**: `IRSA_ROLE_ARN`, `KARPENTER_NODE_ROLE`

The rendered file is intended to be copied to consumer project `.secure_files/` directories and uploaded to GitLab Secure Files as `<env>-k8s-aws.env`.

**Prerequisite:** The cloud, data, and (for ingress) tls stacks must have been applied.

---

## Consumer Usage

### Workspace-Local Invocation (Current)

From a consumer infrastructure repo (e.g. `ami-infrastructure`):

```bash
# Relative path to root-modules-tf in the same workspace
TOOLS=../../../../tomshley-oss-dependencies/root-modules-tf/toolbox/operator-tools

source "$TOOLS/aws-session.sh" .secure_files/staging-us-east-1-cloud.env
source "$TOOLS/k8s-session.sh"
source "$TOOLS/confluent-session.sh" .secure_files/staging-us-east-1-streaming.env
```

### Release Artifact (Future)

Download the operator-tools directory from a GitHub/GitLab release:

```bash
curl -sL https://github.com/tomshley/root-modules-tf/releases/download/v1.4.0/operator-tools.tar.gz | tar xz
source operator-tools/aws-session.sh .secure_files/staging-us-east-1-cloud.env
```

---

## Future Expansion

Terraform-based credential fetchers can be added as subdirectories:

```
toolbox/operator-tools/
├── aws-session.sh
├── confluent-session.sh
├── k8s-session.sh
├── render-streaming-bundle.sh
├── render-ci-deploy-bundle.sh
├── render-k8s-aws-bundle.sh
├── vault-credentials/          # tofu apply → fetches from Vault → writes local .env
│   └── main.tf
├── delinia-credentials/        # same pattern
│   └── main.tf
└── README.md
```

These would use `tofu apply` with local-only state (`.gitignore`d) to fetch short-lived credentials from external secret stores. The state file is ephemeral — it captures no real infrastructure.
