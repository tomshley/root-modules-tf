#!/usr/bin/env bash
# render-service-bundle.sh — Render all TF-derivable secure files for a service.
#
# Reads Terraform/OpenTofu outputs from ami-infrastructure stacks (cloud, data,
# tls, streaming, identity) and writes correctly-formatted .env files directly
# into a target service project's .secure_files/ directory.
#
# This replaces the manual workflow of running individual render scripts,
# copying outputs, and renaming files.
#
# Usage:
#   ./render-service-bundle.sh --service <ingress|structuring|readmodel> \
#     --env <staging|production> --region <region> \
#     --infra-dir <path> --target-dir <path>
#
# Arguments:
#   --service     Required. One of: ingress, structuring, readmodel.
#   --env         Required. Environment name (staging, production).
#   --region      Required. AWS region (e.g. us-east-1).
#   --infra-dir   Required. Path to ami-infrastructure repo root.
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
#   Registry (from .credentials.gitlab — tomshley-cicd convention):
#     <env>-k8s-registry.env    GitLab container registry PAT (auto from .credentials.gitlab)
#
# Requires: tofu (or terraform), make, jq, curl, aws CLI.

set -euo pipefail

TOFU="${TOFU:-tofu}"
RDS_CA_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"

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
      echo "Usage: $0 --service <ingress|structuring|readmodel> --env <env> --region <region> --infra-dir <path> --target-dir <path>" >&2
      exit 1
      ;;
  esac
done

# --- Validate arguments ---
if [[ -z "$SERVICE" ]]; then
  echo "Error: --service is required (ingress, structuring, or readmodel)" >&2; exit 1
fi
if [[ "$SERVICE" != "ingress" && "$SERVICE" != "structuring" && "$SERVICE" != "readmodel" ]]; then
  echo "Error: --service must be 'ingress', 'structuring', or 'readmodel', got '$SERVICE'" >&2; exit 1
fi
if [[ -z "$ENV" ]]; then
  echo "Error: --env is required (e.g. staging, production)" >&2; exit 1
fi
if [[ -z "$REGION" ]]; then
  echo "Error: --region is required (e.g. us-east-1)" >&2; exit 1
fi
if [[ -z "$INFRA_DIR" ]]; then
  echo "Error: --infra-dir is required (path to ami-infrastructure)" >&2; exit 1
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
if [[ "$SERVICE" != "readmodel" ]]; then
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
if [[ "$SERVICE" == "ingress" && ! -d "$TLS_DIR" ]]; then
  echo "Error: tls stack directory not found: $TLS_DIR (required for ingress)" >&2; exit 1
fi
if [[ "$SERVICE" == "readmodel" && ! -d "$IDENTITY_DIR" ]]; then
  echo "Error: stack directory not found: $IDENTITY_DIR (required for readmodel)" >&2; exit 1
fi

SECURE_DIR="${TARGET_DIR}/.secure_files"
mkdir -p "$SECURE_DIR"

if [[ "$SERVICE" == "readmodel" ]]; then
  K8S_NAMESPACE="ami-platform-flattened-read-server-${ENV}"
else
  K8S_NAMESPACE="ami-platform-${SERVICE}-server-${ENV}"
fi
PREFIX="${ENV}-k8s"

if [[ "$SERVICE" == "ingress" ]]; then
  WORKLOAD_KEY="ingress-server"
elif [[ "$SERVICE" == "structuring" ]]; then
  WORKLOAD_KEY="structuring-server"
else
  WORKLOAD_KEY=""
fi

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
# See ami-infrastructure/docs/ci-oidc-setup.md
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
#    Skipped for readmodel (no Kafka interaction).
# =========================================================================
KAFKA_RENDERED=false
if [[ "$SERVICE" != "readmodel" ]] && cd "$STREAMING_DIR" && $TOFU output confluent_configured 2>/dev/null | grep -q "true"; then
  KAFKA_BOOTSTRAP=$($TOFU output -raw kafka_bootstrap_servers 2>/dev/null || echo "")
  SR_URL=$($TOFU output -raw schema_registry_url 2>/dev/null || echo "")

  # Streaming workload keys use ingress-server / structuring-server
  KAFKA_KEY_IDS=$($TOFU output -json workload_kafka_api_key_ids 2>/dev/null || echo "{}")
  KAFKA_SECRETS=$($TOFU output -json workload_kafka_api_secrets 2>/dev/null || echo "{}")
  SR_KEY_IDS=$($TOFU output -json workload_schema_registry_api_key_ids 2>/dev/null || echo "{}")
  SR_SECRETS=$($TOFU output -json workload_schema_registry_api_secrets 2>/dev/null || echo "{}")

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

if [[ "$KAFKA_RENDERED" == "false" && "$SERVICE" != "readmodel" ]]; then
  echo "  ⊘ ${PREFIX}-kafka.env (streaming not configured or workload '$WORKLOAD_KEY' not found)"
  SKIP=$((SKIP + 1))
fi

# =========================================================================
# 4. <env>-k8s-s3-config.env  (from data stack — hyphenated keys for k8s configmap)
#    Skipped for readmodel (no S3 interaction).
# =========================================================================
if [[ "$SERVICE" != "readmodel" ]]; then
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
KEYCLOAK_JWKS_URI=${KEYCLOAK_BASE}/realms/ami/protocol/openid-connect/certs
KEYCLOAK_ISSUER=${KEYCLOAK_BASE}/realms/ami
KEYCLOAK_TOKEN_URL=${KEYCLOAK_BASE}/realms/ami/protocol/openid-connect/token
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
