#!/usr/bin/env bash
# render-service-bundle.sh — Render all TF-derivable secure files for a service.
#
# Reads Terraform/OpenTofu outputs from your infrastructure stacks (cloud, data,
# tls, streaming, identity) and writes correctly-formatted .env files directly
# into a target service project's .secure_files/ directory.
#
# This replaces the manual workflow of running individual render scripts,
# copying outputs, and renaming files.
#
# Usage:
#   ./render-service-bundle.sh --service <ingress|structuring|readmodel|portal> \
#     --env <staging|production> --region <region> \
#     --infra-dir <path> --target-dir <path>
#
# Arguments:
#   --service     Required. One of: ingress, structuring, readmodel, portal.
#   --env         Required. Environment name (staging, production).
#   --region      Required. AWS region (e.g. us-east-1).
#   --infra-dir   Required. Path to the consumer's infrastructure repo root.
#   --target-dir  Required. Path to target service repo root.
#                 Files are written to <target-dir>/.secure_files/.
#
# Output files (all chmod 600):
#
#   All services:
#     <env>-k8s-deploy.env      CI deploy credentials (UPPERCASE keys)
#     <env>-k8s-aws.env         IRSA + Karpenter (UPPERCASE keys)
#
#   Ingress & structuring:
#     <env>-k8s-kafka.env       Kafka + Schema Registry (hyphenated keys for k8s secret)
#     <env>-k8s-s3-config.env   S3 bucket config (hyphenated keys for k8s configmap)
#
#   Ingress only:
#     <env>-k8s-db-config.env       Aurora endpoint (hyphenated keys for k8s configmap)
#     <env>-k8s-db.env              Aurora credentials (hyphenated keys for k8s secret)
#     <env>-k8s-rds-ca-bundle.pem   Amazon RDS root CA certificate
#     <env>-k8s-rds-cert.env        Pointer to the PEM file (for k8s secret)
#
#   Readmodel only:
#     <env>-k8s-keycloak.env        Keycloak identity provider URLs (UPPERCASE keys for k8s configmap)
#     <env>-k8s-db-config.env       Readmodel Aurora endpoint (hyphenated keys for k8s configmap)
#     <env>-k8s-db.env              Readmodel Aurora credentials (hyphenated keys for k8s secret)
#     <env>-k8s-rds-ca-bundle.pem   Amazon RDS root CA certificate
#     <env>-k8s-rds-cert.env        Pointer to the PEM file (for k8s secret)
#
#   Portal only:
#     <env>-k8s-db-config.env       Product-cluster Aurora endpoint + portal tenant DB (hyphenated keys for k8s configmap)
#     <env>-k8s-db.env              Portal tenant Aurora credentials — from the per-tenant app secret, NOT the cluster master secret (hyphenated keys for k8s secret). Populated by the portal migrate Job; script skips with a warning if empty.
#     <env>-k8s-redis.env           Portal Redis connection metadata (hyphenated keys for k8s configmap — AUTH token stays in Secrets Manager and is injected at runtime via ExternalSecrets).
#     <env>-k8s-rds-ca-bundle.pem   Amazon RDS root CA certificate
#     <env>-k8s-rds-cert.env        Pointer to the PEM file (for k8s secret)
#
#   Registry (from .credentials.gitlab — tomshley-cicd convention):
#     <env>-k8s-registry.env    GitLab container registry PAT (auto from .credentials.gitlab)
#
# Requires: tofu (or terraform), make, jq, curl, aws CLI.

set -euo pipefail

TOFU="${TOFU:-tofu}"
RDS_CA_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"

# Keycloak realm is consumer-specific. Override at invocation time, e.g.
# `KEYCLOAK_REALM=myrealm ./render-service-bundle.sh ...`. The default is a
# generic placeholder that consumer stacks must replace; leaving the default
# in place will produce a keycloak.env that points at /realms/myrealm and
# will fail at runtime against any Keycloak deployment that does not host
# that realm. Eventually this should come from an `identity` stack output
# (e.g. `keycloak_realm_name`); plumbing that is out of scope for this
# change. See README for the recommended override.
KEYCLOAK_REALM="${KEYCLOAK_REALM:-myrealm}"

# K8S namespace prefix is consumer-specific (everything before the per-service
# variant in the rendered K8S_NAMESPACE). Override at invocation time, e.g.
# `K8S_NAMESPACE_PREFIX=myapp-platform ./render-service-bundle.sh ...`. The
# default is a generic placeholder; consumer stacks must replace it. Eventually
# this should come from a `cloud` stack output (e.g. `k8s_namespace_prefix`);
# plumbing that is out of scope for this change. See README for the recommended
# override.
K8S_NAMESPACE_PREFIX="${K8S_NAMESPACE_PREFIX:-myapp-platform}"

# --- Parse arguments ---
SERVICE=""
ENV=""
REGION=""
INFRA_DIR=""
TARGET_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)    SERVICE="$2";    shift 2 ;;
    --env)        ENV="$2";        shift 2 ;;
    --region)     REGION="$2";     shift 2 ;;
    --infra-dir)  INFRA_DIR="$2";  shift 2 ;;
    --target-dir) TARGET_DIR="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --service <ingress|structuring|readmodel|portal> --env <env> --region <region> --infra-dir <path> --target-dir <path>" >&2
      exit 1
      ;;
  esac
done

# --- Validate arguments ---
if [[ -z "$SERVICE" ]]; then
  echo "Error: --service is required (ingress, structuring, readmodel, or portal)" >&2; exit 1
fi
if [[ "$SERVICE" != "ingress" && "$SERVICE" != "structuring" && "$SERVICE" != "readmodel" && "$SERVICE" != "portal" ]]; then
  echo "Error: --service must be 'ingress', 'structuring', 'readmodel', or 'portal', got '$SERVICE'" >&2; exit 1
fi
if [[ -z "$ENV" ]]; then
  echo "Error: --env is required (e.g. staging, production)" >&2; exit 1
fi
if [[ -z "$REGION" ]]; then
  echo "Error: --region is required (e.g. us-east-1)" >&2; exit 1
fi
if [[ -z "$INFRA_DIR" ]]; then
  echo "Error: --infra-dir is required (path to the consumer's infrastructure repo)" >&2; exit 1
fi
if [[ -z "$TARGET_DIR" ]]; then
  echo "Error: --target-dir is required (path to service repo)" >&2; exit 1
fi

for cmd in jq curl aws; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not found in PATH" >&2; exit 1
  fi
done

# --- Derive stack paths ---
ENVS_BASE="${INFRA_DIR}/environments/${ENV}/${REGION}"
CLOUD_DIR="${ENVS_BASE}/cloud"
DATA_DIR="${ENVS_BASE}/data"
TLS_DIR="${ENVS_BASE}/tls"
STREAMING_DIR="${ENVS_BASE}/streaming"
IDENTITY_DIR="${ENVS_BASE}/identity"

# cloud is required for all services
if [[ ! -d "$CLOUD_DIR" ]]; then
  echo "Error: stack directory not found: $CLOUD_DIR" >&2; exit 1
fi
# data + streaming required for ingress/structuring
if [[ "$SERVICE" == "ingress" || "$SERVICE" == "structuring" ]]; then
  for dir in "$DATA_DIR" "$STREAMING_DIR"; do
    if [[ ! -d "$dir" ]]; then
      echo "Error: stack directory not found: $dir" >&2; exit 1
    fi
  done
fi
# data required for readmodel (readmodel Aurora outputs)
if [[ "$SERVICE" == "readmodel" && ! -d "$DATA_DIR" ]]; then
  echo "Error: stack directory not found: $DATA_DIR (required for readmodel)" >&2; exit 1
fi
# data + tls required for portal (product cluster tenant outputs + portal ACM cert)
if [[ "$SERVICE" == "portal" ]]; then
  for dir in "$DATA_DIR" "$TLS_DIR"; do
    if [[ ! -d "$dir" ]]; then
      echo "Error: stack directory not found: $dir (required for portal)" >&2; exit 1
    fi
  done
fi
if [[ "$SERVICE" == "ingress" && ! -d "$TLS_DIR" ]]; then
  echo "Error: tls stack directory not found: $TLS_DIR (required for ingress)" >&2; exit 1
fi
if [[ "$SERVICE" == "readmodel" && ! -d "$IDENTITY_DIR" ]]; then
  echo "Error: stack directory not found: $IDENTITY_DIR (required for readmodel)" >&2; exit 1
fi

SECURE_DIR="${TARGET_DIR}/.secure_files"
mkdir -p "$SECURE_DIR"

if [[ "$SERVICE" == "readmodel" ]]; then
  K8S_NAMESPACE="${K8S_NAMESPACE_PREFIX}-flattened-read-server-${ENV}"
else
  # ingress / structuring / portal all follow the same naming convention.
  K8S_NAMESPACE="${K8S_NAMESPACE_PREFIX}-${SERVICE}-server-${ENV}"
fi
PREFIX="${ENV}-k8s"

if [[ "$SERVICE" == "ingress" ]]; then
  WORKLOAD_KEY="ingress-server"
elif [[ "$SERVICE" == "structuring" ]]; then
  WORKLOAD_KEY="structuring-server"
else
  # readmodel and portal do not participate in the Confluent workload-key
  # map, so there is no Kafka API key lookup for them.
  WORKLOAD_KEY=""
fi

# Portal tenant key inside the product-cluster multi-tenant Aurora outputs.
# Keeping this as a single-source-of-truth variable means the tenant rename
# (e.g. 'portal' → 'portal-server') would be a one-line edit here rather
# than a grep-and-replace through the portal branch below.
PORTAL_TENANT_KEY="portal"

echo "Rendering $SERVICE bundle for $ENV/$REGION"
echo "  infra-dir:  $INFRA_DIR"
echo "  target-dir: $TARGET_DIR"
echo "  namespace:  $K8S_NAMESPACE"
echo "  workload:   $WORKLOAD_KEY"
echo ""

# --- Helper: read a single TF output ---
read_output() {
  local dir="$1" key="$2" val=""
  val=$(cd "$dir" && make output 2>/dev/null \
    | grep -E "^${key}\s" \
    | sed 's/.*= *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "")
  if [[ -z "$val" ]]; then
    val=$(cd "$dir" && $TOFU output -raw "$key" 2>/dev/null || echo "")
  fi
  echo "$val"
}

require_output() {
  local val="$1" name="$2" stack="$3"
  if [[ -z "$val" ]]; then
    echo "Error: $name output is empty or missing from $stack stack." >&2
    echo "Has the stack been applied? Run: make -C <stack-dir> output" >&2
    exit 1
  fi
}

OK=0
SKIP=0

emit() {
  local file="$1"
  chmod 600 "$file"
  echo "  ✓ $(basename "$file")"
  OK=$((OK + 1))
}

# =========================================================================
# 1. <env>-k8s-deploy.env  (from cloud stack)
# =========================================================================
CLUSTER_NAME=$(read_output "$CLOUD_DIR" cluster_name)
require_output "$CLUSTER_NAME" "cluster_name" "cloud"

CI_DEPLOY_ROLE_ARN=$(read_output "$CLOUD_DIR" ci_deploy_role_arn)
require_output "$CI_DEPLOY_ROLE_ARN" "ci_deploy_role_arn" "cloud"

cat > "${SECURE_DIR}/${PREFIX}-deploy.env" <<EOF
# CI deploy credentials for ${ENV} — rendered by render-service-bundle.sh
# See <infra-repo>/docs/ci-oidc-setup.md
AWS_DEFAULT_REGION=$REGION
AWS_REGION=$REGION
K8S_CLUSTER_NAME=$CLUSTER_NAME
CI_DEPLOY_ROLE_ARN=$CI_DEPLOY_ROLE_ARN
K8S_NAMESPACE=$K8S_NAMESPACE
EOF
emit "${SECURE_DIR}/${PREFIX}-deploy.env"

# =========================================================================
# 2. <env>-k8s-aws.env  (from cloud + data + tls stacks)
# =========================================================================
KARPENTER_NODE_ROLE=$(read_output "$CLOUD_DIR" karpenter_node_role_name)
require_output "$KARPENTER_NODE_ROLE" "karpenter_node_role_name" "cloud"

if [[ "$SERVICE" == "ingress" ]]; then
  IRSA_ROLE_ARN=$(read_output "$DATA_DIR" ingress_irsa_role_arn)
  require_output "$IRSA_ROLE_ARN" "ingress_irsa_role_arn" "data"

  ACM_CERT_ARN=$(read_output "$TLS_DIR" certificate_arn)
  require_output "$ACM_CERT_ARN" "certificate_arn" "tls"

  cat > "${SECURE_DIR}/${PREFIX}-aws.env" <<EOF
# AWS resource ARNs and Karpenter node role for ingress
# Rendered by render-service-bundle.sh from tls, data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
ACM_CERT_ARN=$ACM_CERT_ARN
IRSA_ROLE_ARN=$IRSA_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
elif [[ "$SERVICE" == "readmodel" ]]; then
  IRSA_ROLE_ARN=$(read_output "$DATA_DIR" readserver_irsa_role_arn)
  require_output "$IRSA_ROLE_ARN" "readserver_irsa_role_arn" "data"

  ACM_CERT_ARN=$(read_output "$TLS_DIR" certificate_arn)
  require_output "$ACM_CERT_ARN" "certificate_arn" "tls"

  cat > "${SECURE_DIR}/${PREFIX}-aws.env" <<EOF
# IRSA role ARN, ACM cert, and Karpenter node role for readmodel
# Rendered by render-service-bundle.sh from tls, data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
ACM_CERT_ARN=$ACM_CERT_ARN
IRSA_ROLE_ARN=$IRSA_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
elif [[ "$SERVICE" == "portal" ]]; then
  # Portal uses the product-cluster multi-tenant Aurora pattern (one DB
  # per service on a shared cluster), so APP and MIGRATE IRSA are separate
  # roles. The app role has read on the portal tenant's app secret only;
  # the migrate role has master-secret read + portal-tenant-secret write.
  # Never conflate: a compromised migrate pod holds cluster-superuser
  # credentials. See aws-eks-aurora-cluster's tenant documentation.
  APP_ROLE_MAP=$(cd "$DATA_DIR" && $TOFU output -json product_tenant_app_role_arns 2>/dev/null || echo "{}")
  MIGRATE_ROLE_MAP=$(cd "$DATA_DIR" && $TOFU output -json product_tenant_migrate_role_arns 2>/dev/null || echo "{}")
  APP_SECRET_MAP=$(cd "$DATA_DIR" && $TOFU output -json product_tenant_secret_arns 2>/dev/null || echo "{}")

  APP_IRSA_ROLE_ARN=$(echo "$APP_ROLE_MAP" | jq -r --arg k "$PORTAL_TENANT_KEY" '.[$k] // empty')
  MIGRATE_IRSA_ROLE_ARN=$(echo "$MIGRATE_ROLE_MAP" | jq -r --arg k "$PORTAL_TENANT_KEY" '.[$k] // empty')
  APP_SECRET_ARN=$(echo "$APP_SECRET_MAP" | jq -r --arg k "$PORTAL_TENANT_KEY" '.[$k] // empty')

  require_output "$APP_IRSA_ROLE_ARN" "product_tenant_app_role_arns[$PORTAL_TENANT_KEY]" "data"
  require_output "$MIGRATE_IRSA_ROLE_ARN" "product_tenant_migrate_role_arns[$PORTAL_TENANT_KEY]" "data"
  require_output "$APP_SECRET_ARN" "product_tenant_secret_arns[$PORTAL_TENANT_KEY]" "data"

  REDIS_AUTH_SECRET_ARN=$(read_output "$DATA_DIR" portal_redis_auth_token_secret_arn)
  require_output "$REDIS_AUTH_SECRET_ARN" "portal_redis_auth_token_secret_arn" "data"

  APPSTREAM_ROLE_ARN=$(read_output "$DATA_DIR" portal_appstream_cross_account_role_arn)
  require_output "$APPSTREAM_ROLE_ARN" "portal_appstream_cross_account_role_arn" "data"

  # Portal ACM cert may be provisioned as a dedicated certificate
  # (portal_certificate_arn) or as a SAN on the ingress cert
  # (certificate_arn). Prefer the portal-specific output when present;
  # fall back to the shared ingress cert so operators who chose the SAN
  # approach do not have to re-run Terraform to satisfy this renderer.
  # Log which one was selected so audit of CI logs answers "which cert
  # is portal using?" without re-running `tofu output`.
  ACM_CERT_ARN=$(read_output "$TLS_DIR" portal_certificate_arn)
  if [[ -n "$ACM_CERT_ARN" ]]; then
    echo "  ⓘ portal ACM cert: using portal_certificate_arn (dedicated portal cert)"
  else
    ACM_CERT_ARN=$(read_output "$TLS_DIR" certificate_arn)
    if [[ -n "$ACM_CERT_ARN" ]]; then
      echo "  ⓘ portal ACM cert: using certificate_arn (shared ingress cert with portal SAN; no portal_certificate_arn output)"
    fi
  fi
  require_output "$ACM_CERT_ARN" "portal_certificate_arn or certificate_arn" "tls"

  cat > "${SECURE_DIR}/${PREFIX}-aws.env" <<EOF
# IRSA roles, ACM cert, Redis AUTH secret, AppStream cross-account role,
# and Karpenter node role for portal
# Rendered by render-service-bundle.sh from tls, data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
#
# NOTE on IAM policy wiring (out of scope for this renderer):
#   REDIS_AUTH_SECRET_ARN is the ARN of the Secrets Manager secret the
#   portal runtime reads for the Redis AUTH token. The IAM policy that
#   grants secretsmanager:GetSecretValue + DescribeSecret on that secret
#   (the aws-eks-elasticache-redis module's app_read_policy_arn output)
#   must be attached to the portal APP IRSA role in the consumer's
#   infrastructure data stack -- not here. This renderer emits the ARNs consumers need
#   at runtime; it does not mutate IAM.
ACM_CERT_ARN=$ACM_CERT_ARN
APP_IRSA_ROLE_ARN=$APP_IRSA_ROLE_ARN
MIGRATE_IRSA_ROLE_ARN=$MIGRATE_IRSA_ROLE_ARN
APP_SECRET_ARN=$APP_SECRET_ARN
REDIS_AUTH_SECRET_ARN=$REDIS_AUTH_SECRET_ARN
APPSTREAM_ROLE_ARN=$APPSTREAM_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
else
  IRSA_ROLE_ARN=$(read_output "$DATA_DIR" structuring_irsa_role_arn)
  require_output "$IRSA_ROLE_ARN" "structuring_irsa_role_arn" "data"

  cat > "${SECURE_DIR}/${PREFIX}-aws.env" <<EOF
# IRSA role ARN and Karpenter node role for structuring
# Rendered by render-service-bundle.sh from data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
IRSA_ROLE_ARN=$IRSA_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
fi
emit "${SECURE_DIR}/${PREFIX}-aws.env"

# =========================================================================
# 3. <env>-k8s-kafka.env  (from streaming stack — hyphenated keys for k8s secret)
#    Skipped for readmodel and portal (no Kafka interaction).
# =========================================================================
KAFKA_RENDERED=false
# Wrap the streaming-stack lookups in an explicit subshell so the `cd`
# does not leak the script's working directory into the portal/registry
# blocks below. Earlier revisions used a top-level `cd "$STREAMING_DIR"`
# inside the `if` test, which technically worked because every later
# `read_output` re-establishes its own CWD via its own subshell -- but
# any future helper that resolved a relative path against $PWD would
# silently bind against STREAMING_DIR after this block ran.
if [[ "$SERVICE" != "readmodel" && "$SERVICE" != "portal" ]] \
  && (cd "$STREAMING_DIR" && $TOFU output confluent_configured 2>/dev/null | grep -q "true"); then
  KAFKA_BOOTSTRAP=$(cd "$STREAMING_DIR" && $TOFU output -raw kafka_bootstrap_servers 2>/dev/null || echo "")
  SR_URL=$(cd "$STREAMING_DIR" && $TOFU output -raw schema_registry_url 2>/dev/null || echo "")

  # Streaming workload keys use ingress-server / structuring-server
  KAFKA_KEY_IDS=$(cd "$STREAMING_DIR" && $TOFU output -json workload_kafka_api_key_ids 2>/dev/null || echo "{}")
  KAFKA_SECRETS=$(cd "$STREAMING_DIR" && $TOFU output -json workload_kafka_api_secrets 2>/dev/null || echo "{}")
  SR_KEY_IDS=$(cd "$STREAMING_DIR" && $TOFU output -json workload_schema_registry_api_key_ids 2>/dev/null || echo "{}")
  SR_SECRETS=$(cd "$STREAMING_DIR" && $TOFU output -json workload_schema_registry_api_secrets 2>/dev/null || echo "{}")

  KAFKA_KEY=$(echo "$KAFKA_KEY_IDS" | jq -r --arg w "$WORKLOAD_KEY" '.[$w] // empty')
  KAFKA_SECRET=$(echo "$KAFKA_SECRETS" | jq -r --arg w "$WORKLOAD_KEY" '.[$w] // empty')
  SR_KEY=$(echo "$SR_KEY_IDS" | jq -r --arg w "$WORKLOAD_KEY" '.[$w] // empty')
  SR_SECRET=$(echo "$SR_SECRETS" | jq -r --arg w "$WORKLOAD_KEY" '.[$w] // empty')

  if [[ -n "$KAFKA_BOOTSTRAP" && -n "$KAFKA_KEY" ]]; then
    cat > "${SECURE_DIR}/${PREFIX}-kafka.env" <<EOF
bootstrap-servers=$KAFKA_BOOTSTRAP
api-key=$KAFKA_KEY
api-secret=$KAFKA_SECRET
schema-registry-url=$SR_URL
schema-registry-api-key=$SR_KEY
schema-registry-api-secret=$SR_SECRET
EOF
    emit "${SECURE_DIR}/${PREFIX}-kafka.env"
    KAFKA_RENDERED=true
  fi
fi

if [[ "$KAFKA_RENDERED" == "false" && "$SERVICE" != "readmodel" && "$SERVICE" != "portal" ]]; then
  echo "  ⊘ ${PREFIX}-kafka.env (streaming not configured or workload '$WORKLOAD_KEY' not found)"
  SKIP=$((SKIP + 1))
fi

# =========================================================================
# 4. <env>-k8s-s3-config.env  (from data stack — hyphenated keys for k8s configmap)
#    Skipped for readmodel and portal (no S3 interaction).
# =========================================================================
if [[ "$SERVICE" != "readmodel" && "$SERVICE" != "portal" ]]; then
  BUCKET_NAME=$(read_output "$DATA_DIR" chunk_bucket_name)
  require_output "$BUCKET_NAME" "chunk_bucket_name" "data"

  cat > "${SECURE_DIR}/${PREFIX}-s3-config.env" <<EOF
bucket-name=$BUCKET_NAME
region=$REGION
EOF
  emit "${SECURE_DIR}/${PREFIX}-s3-config.env"
fi

# =========================================================================
# Ingress-only files
# =========================================================================
if [[ "$SERVICE" == "ingress" ]]; then

  # 5. <env>-k8s-db-config.env  (from data stack — hyphenated keys for k8s configmap)
  DB_HOST=$(read_output "$DATA_DIR" aurora_cluster_endpoint)
  DB_PORT=$(read_output "$DATA_DIR" aurora_port)
  DB_NAME=$(read_output "$DATA_DIR" aurora_database_name)
  require_output "$DB_HOST" "aurora_cluster_endpoint" "data"

  cat > "${SECURE_DIR}/${PREFIX}-db-config.env" <<EOF
host=$DB_HOST
port=${DB_PORT:-5432}
database=${DB_NAME:-postgres}
EOF
  emit "${SECURE_DIR}/${PREFIX}-db-config.env"

  # 6. <env>-k8s-db.env  (from Secrets Manager — hyphenated keys for k8s secret)
  SECRET_ARN=$(read_output "$DATA_DIR" aurora_master_secret_arn)
  if [[ -n "$SECRET_ARN" ]]; then
    SECRET_JSON=$(aws secretsmanager get-secret-value \
      --secret-id "$SECRET_ARN" --region "$REGION" \
      --query SecretString --output text 2>/dev/null || echo "")
    if [[ -n "$SECRET_JSON" ]]; then
      DB_USER=$(echo "$SECRET_JSON" | jq -r '.username // "postgres"')
      DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password // empty')
      if [[ -n "$DB_PASS" ]]; then
        cat > "${SECURE_DIR}/${PREFIX}-db.env" <<EOF
username=$DB_USER
password=$DB_PASS
EOF
        emit "${SECURE_DIR}/${PREFIX}-db.env"
      else
        echo "  ⊘ ${PREFIX}-db.env (password empty in Secrets Manager)" >&2
        SKIP=$((SKIP + 1))
      fi
    else
      echo "  ⊘ ${PREFIX}-db.env (could not read Secrets Manager: $SECRET_ARN)" >&2
      SKIP=$((SKIP + 1))
    fi
  else
    echo "  ⊘ ${PREFIX}-db.env (aurora_master_secret_arn not in data stack outputs)" >&2
    SKIP=$((SKIP + 1))
  fi

  # 7. <env>-k8s-rds-ca-bundle.pem  (downloaded from Amazon)
  PEM_FILE="${SECURE_DIR}/${PREFIX}-rds-ca-bundle.pem"
  if curl -sfL "$RDS_CA_URL" -o "$PEM_FILE"; then
    chmod 600 "$PEM_FILE"
    echo "  ✓ ${PREFIX}-rds-ca-bundle.pem (downloaded)"
    OK=$((OK + 1))
  else
    echo "  ⊘ ${PREFIX}-rds-ca-bundle.pem (download failed: $RDS_CA_URL)" >&2
    SKIP=$((SKIP + 1))
  fi

  # 8. <env>-k8s-rds-cert.env  (pointer to PEM)
  cat > "${SECURE_DIR}/${PREFIX}-rds-cert.env" <<EOF
rds-ca-bundle.pem=.secure_files/${PREFIX}-rds-ca-bundle.pem
EOF
  emit "${SECURE_DIR}/${PREFIX}-rds-cert.env"

fi

# =========================================================================
# Readmodel-only files
# =========================================================================
if [[ "$SERVICE" == "readmodel" ]]; then

  # 5r. <env>-k8s-keycloak.env  (from identity stack — UPPERCASE keys for k8s configmap)
  KEYCLOAK_NS=$(read_output "$IDENTITY_DIR" keycloak_release_namespace)
  KEYCLOAK_SVC=$(read_output "$IDENTITY_DIR" keycloak_service_name)
  KEYCLOAK_PORT=$(read_output "$IDENTITY_DIR" keycloak_service_port)
  require_output "$KEYCLOAK_NS" "keycloak_release_namespace" "identity"
  require_output "$KEYCLOAK_SVC" "keycloak_service_name" "identity"
  require_output "$KEYCLOAK_PORT" "keycloak_service_port" "identity"

  KEYCLOAK_BASE="http://${KEYCLOAK_SVC}.${KEYCLOAK_NS}.svc.cluster.local:${KEYCLOAK_PORT}"

  cat > "${SECURE_DIR}/${PREFIX}-keycloak.env" <<EOF
# Keycloak identity provider URLs (cluster-internal)
# Rendered by render-service-bundle.sh from identity stack outputs
KEYCLOAK_JWKS_URI=${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/certs
KEYCLOAK_ISSUER=${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}
KEYCLOAK_TOKEN_URL=${KEYCLOAK_BASE}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token
EOF
  emit "${SECURE_DIR}/${PREFIX}-keycloak.env"

  # 6r. <env>-k8s-db-config.env  (readmodel Aurora — hyphenated keys for k8s configmap)
  DB_HOST=$(read_output "$DATA_DIR" readmodel_cluster_endpoint)
  DB_PORT=$(read_output "$DATA_DIR" readmodel_port)
  require_output "$DB_HOST" "readmodel_cluster_endpoint" "data"

  cat > "${SECURE_DIR}/${PREFIX}-db-config.env" <<EOF
host=$DB_HOST
port=${DB_PORT:-5432}
EOF
  emit "${SECURE_DIR}/${PREFIX}-db-config.env"

  # 7r. <env>-k8s-db.env  (readmodel Aurora credentials — hyphenated keys for k8s secret)
  SECRET_ARN=$(read_output "$DATA_DIR" readmodel_master_secret_arn)
  if [[ -n "$SECRET_ARN" ]]; then
    SECRET_JSON=$(aws secretsmanager get-secret-value \
      --secret-id "$SECRET_ARN" --region "$REGION" \
      --query SecretString --output text 2>/dev/null || echo "")
    if [[ -n "$SECRET_JSON" ]]; then
      DB_USER=$(echo "$SECRET_JSON" | jq -r '.username // "postgres"')
      DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password // empty')
      if [[ -n "$DB_PASS" ]]; then
        cat > "${SECURE_DIR}/${PREFIX}-db.env" <<EOF
username=$DB_USER
password=$DB_PASS
EOF
        emit "${SECURE_DIR}/${PREFIX}-db.env"
      else
        echo "  ⊘ ${PREFIX}-db.env (password empty in Secrets Manager)" >&2
        SKIP=$((SKIP + 1))
      fi
    else
      echo "  ⊘ ${PREFIX}-db.env (could not read Secrets Manager: $SECRET_ARN)" >&2
      SKIP=$((SKIP + 1))
    fi
  else
    echo "  ⊘ ${PREFIX}-db.env (readmodel_master_secret_arn not in data stack outputs)" >&2
    SKIP=$((SKIP + 1))
  fi

  # 8r. <env>-k8s-rds-ca-bundle.pem  (downloaded from Amazon)
  PEM_FILE="${SECURE_DIR}/${PREFIX}-rds-ca-bundle.pem"
  if curl -sfL "$RDS_CA_URL" -o "$PEM_FILE"; then
    chmod 600 "$PEM_FILE"
    echo "  ✓ ${PREFIX}-rds-ca-bundle.pem (downloaded)"
    OK=$((OK + 1))
  else
    echo "  ⊘ ${PREFIX}-rds-ca-bundle.pem (download failed: $RDS_CA_URL)" >&2
    SKIP=$((SKIP + 1))
  fi

  # 9r. <env>-k8s-rds-cert.env  (pointer to PEM)
  cat > "${SECURE_DIR}/${PREFIX}-rds-cert.env" <<EOF
rds-ca-bundle.pem=.secure_files/${PREFIX}-rds-ca-bundle.pem
EOF
  emit "${SECURE_DIR}/${PREFIX}-rds-cert.env"

fi

# =========================================================================
# Portal-only files
# =========================================================================
if [[ "$SERVICE" == "portal" ]]; then

  # 5p. <env>-k8s-db-config.env  (product-cluster endpoint + portal tenant DB — hyphenated keys for k8s configmap)
  #
  # host/port are sourced from the stack output (product_cluster_endpoint /
  # product_port), NOT from the portal tenant app secret. Two reasons:
  #   (1) The cluster endpoint is the authoritative DNS record AWS
  #       resolves to the current writer, and Terraform guarantees it
  #       survives in-place Aurora changes including blue-green
  #       cut-overs that the tenant app secret's embedded host/port may
  #       lag behind (the migrate Job only refreshes the secret when
  #       re-run).
  #   (2) The tenant app secret is populated by the migrate Job and may
  #       not yet exist on a first-ever render; failing here would
  #       block CI before the migrate Job has had a chance to run.
  # Consumers that want DB credentials read the tenant app secret at
  # runtime via ExternalSecrets using APP_SECRET_ARN (emitted above).
  DB_HOST=$(read_output "$DATA_DIR" product_cluster_endpoint)
  DB_PORT=$(read_output "$DATA_DIR" product_port)
  require_output "$DB_HOST" "product_cluster_endpoint" "data"

  # Tenant database name is declared in var.tenants in the data stack and
  # re-exported via product_tenant_database_names. We fail hard on a
  # missing key rather than falling back to a convention name
  # (e.g. some hardcoded '<prefix>_portal' default): the earlier require_output on
  # product_tenant_app_role_arns[portal] has already proved the tenant
  # is registered, so a missing database_names entry is a data-stack
  # output-set mismatch that must surface, not a case to paper over
  # with a guess that silently points portal at a non-existent DB.
  DB_NAME_MAP=$(cd "$DATA_DIR" && $TOFU output -json product_tenant_database_names 2>/dev/null || echo "{}")
  DB_NAME=$(echo "$DB_NAME_MAP" | jq -r --arg k "$PORTAL_TENANT_KEY" '.[$k] // empty')
  require_output "$DB_NAME" "product_tenant_database_names[$PORTAL_TENANT_KEY]" "data"

  cat > "${SECURE_DIR}/${PREFIX}-db-config.env" <<EOF
host=$DB_HOST
port=${DB_PORT:-5432}
database=$DB_NAME
ssl=require
EOF
  emit "${SECURE_DIR}/${PREFIX}-db-config.env"

  # 6p. <env>-k8s-db.env  (portal tenant Aurora credentials — hyphenated keys for k8s secret)
  #
  # CRITICAL: portal reads its tenant app secret (populated by the portal
  # migrate Job), NOT the cluster master secret. Using the master secret
  # here would grant portal runtime the cluster-superuser credential,
  # violating minimum-necessary and the multi-tenant threat model
  # documented in aws-eks-aurora-cluster's tenant variable.
  #
  # The tenant secret is intentionally empty until the first successful
  # portal migrate Job populates it. Skipping with a clear warning is
  # preferable to writing empty fields that would silently break portal
  # startup.
  #
  # APP_SECRET_ARN is guaranteed non-empty here: require_output above
  # already exited if it was missing, so no outer empty-ARN branch is
  # needed.
  #
  # Failure-mode mapping (this is operationally critical — pre-pass-6
  # the comment block here had it backwards and the user-facing message
  # for the most common pre-migrate state mis-routed operators to chase
  # phantom IAM problems):
  #
  #   Migrate Job has NOT yet run
  #     → the Aurora module created `aws_secretsmanager_secret.tenant`
  #       as an empty placeholder (no aws_secretsmanager_secret_version)
  #     → `aws secretsmanager get-secret-value` returns
  #       ResourceNotFoundException ("can't find the specified secret
  #       value for staging label: AWSCURRENT") and exits non-zero
  #     → SECRET_JSON="" (rescued by `2>/dev/null || echo ""`)
  #     → outer else fires
  #
  #   Migrate Job ran, secret has version, but version JSON is missing
  #   the username or password fields (atypical — only happens if the
  #   migrate Job partially populated the secret)
  #     → SECRET_JSON contains the version payload
  #     → inner if/else fires; inner else surfaces the "fields missing"
  #       case as defense-in-depth
  #
  #   Real Secrets-Manager read failure (no permission, secret deleted,
  #   network failure, KMS Decrypt denied)
  #     → aws CLI exits non-zero, SECRET_JSON=""
  #     → outer else fires (sharing the path with migrate-not-yet-run)
  #
  # The outer-else message therefore leads with the most likely cause
  # (migrate not yet run on a fresh portal tenant) and lists the rarer
  # IAM/network causes after, so operators look at the migrate-Job
  # status before chasing IRSA/VPCE/SCP.
  SECRET_JSON=$(aws secretsmanager get-secret-value \
    --secret-id "$APP_SECRET_ARN" --region "$REGION" \
    --query SecretString --output text 2>/dev/null || echo "")
  if [[ -n "$SECRET_JSON" ]]; then
    DB_USER=$(echo "$SECRET_JSON" | jq -r '.username // empty')
    DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password // empty')
    if [[ -n "$DB_USER" && -n "$DB_PASS" ]]; then
      cat > "${SECURE_DIR}/${PREFIX}-db.env" <<EOF
username=$DB_USER
password=$DB_PASS
EOF
      emit "${SECURE_DIR}/${PREFIX}-db.env"
    else
      echo "  ⊘ ${PREFIX}-db.env (portal tenant secret has a version but is missing username/password — migrate Job partially populated the secret; inspect $APP_SECRET_ARN and re-run migrate)" >&2
      SKIP=$((SKIP + 1))
    fi
  else
    echo "  ⊘ ${PREFIX}-db.env (most likely the portal migrate Job has not yet run and the tenant secret has no version; less likely: missing IAM permission on $APP_SECRET_ARN, secret deleted, network failure, or KMS Decrypt denied)" >&2
    SKIP=$((SKIP + 1))
  fi

  # 7p. <env>-k8s-redis.env  (portal Redis connection metadata — hyphenated keys for k8s configmap)
  #
  # AUTH token is NOT written here. Consumers read it from Secrets Manager
  # at runtime via ExternalSecrets or the Secrets Manager CSI driver,
  # using REDIS_AUTH_SECRET_ARN (emitted in aws.env above). Writing the
  # AUTH token to a configmap-style file would defeat the reason the
  # module produced a Secrets-Manager-scoped IAM policy in the first
  # place.
  REDIS_HOST=$(read_output "$DATA_DIR" portal_redis_primary_endpoint)
  REDIS_PORT=$(read_output "$DATA_DIR" portal_redis_port)
  require_output "$REDIS_HOST" "portal_redis_primary_endpoint" "data"

  cat > "${SECURE_DIR}/${PREFIX}-redis.env" <<EOF
host=$REDIS_HOST
port=${REDIS_PORT:-6379}
tls=true
EOF
  emit "${SECURE_DIR}/${PREFIX}-redis.env"

  # 8p. <env>-k8s-rds-ca-bundle.pem  (downloaded from Amazon)
  PEM_FILE="${SECURE_DIR}/${PREFIX}-rds-ca-bundle.pem"
  if curl -sfL "$RDS_CA_URL" -o "$PEM_FILE"; then
    chmod 600 "$PEM_FILE"
    echo "  ✓ ${PREFIX}-rds-ca-bundle.pem (downloaded)"
    OK=$((OK + 1))
  else
    echo "  ⊘ ${PREFIX}-rds-ca-bundle.pem (download failed: $RDS_CA_URL)" >&2
    SKIP=$((SKIP + 1))
  fi

  # 9p. <env>-k8s-rds-cert.env  (pointer to PEM)
  cat > "${SECURE_DIR}/${PREFIX}-rds-cert.env" <<EOF
rds-ca-bundle.pem=.secure_files/${PREFIX}-rds-ca-bundle.pem
EOF
  emit "${SECURE_DIR}/${PREFIX}-rds-cert.env"

fi

# =========================================================================
# 9. <env>-k8s-registry.env  (from .credentials.gitlab — tomshley-cicd convention)
# =========================================================================
CREDS_FILE="${SECURE_DIR}/.credentials.gitlab"
REGISTRY_FILE="${SECURE_DIR}/${PREFIX}-registry.env"

if [[ -f "$CREDS_FILE" ]]; then
  # Parse user/password from .credentials.gitlab (KEY=value format)
  CREDS_USER=$(grep -E '^user=' "$CREDS_FILE" | head -1 | cut -d= -f2-)
  CREDS_PASS=$(grep -E '^password=' "$CREDS_FILE" | head -1 | cut -d= -f2-)
  if [[ -n "$CREDS_USER" && -n "$CREDS_PASS" ]]; then
    cat > "$REGISTRY_FILE" <<EOF
# GitLab Container Registry credentials for K8s imagePullSecrets (read-only pull)
# Sourced from .credentials.gitlab by render-service-bundle.sh
REGISTRY_USER=$CREDS_USER
REGISTRY_TOKEN=$CREDS_PASS
EOF
    emit "$REGISTRY_FILE"
  else
    echo "  ⊘ ${PREFIX}-registry.env (.credentials.gitlab missing user or password)" >&2
    SKIP=$((SKIP + 1))
  fi
else
  echo "  ⊘ ${PREFIX}-registry.env (no .credentials.gitlab found — create manually or add .credentials.gitlab)" >&2
  SKIP=$((SKIP + 1))
fi

# =========================================================================
# Summary
# =========================================================================
echo ""
echo "Done: $OK rendered, $SKIP skipped"

if [[ ! -f "$CREDS_FILE" ]]; then
  echo ""
  echo "To enable auto-generation of ${PREFIX}-registry.env, add:"
  echo "  ${CREDS_FILE}"
  echo "  Format: realm=... host=... user=<gitlab-user> password=<gitlab-pat>"
fi

echo ""
echo "Next steps:"
echo "  1. Review files: ls -la ${SECURE_DIR}/"
echo "  2. Upload to GitLab Secure Files:"
echo "     sync-secure-files.sh --project-id <id> --secure-dir ${SECURE_DIR}"
