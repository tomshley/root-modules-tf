#!/usr/bin/env bash
# confluent-bootstrap.sh — Bootstrap Confluent Cloud service accounts, API keys, and ACLs.
#
# Requires: confluent CLI (v3+), jq
#
# This script uses the operator's personal Confluent Cloud login to create the
# service accounts and API keys that Terraform needs to manage a streaming stack.
# Once the bootstrap is complete, the operator's login is no longer required —
# Terraform authenticates with the created Cloud API key.
#
# Usage:
#   ./confluent-bootstrap.sh \
#     --environment  env-XXXXX \
#     --cluster      lkc-XXXXX \
#     --tf-sa-name   tf-my-infrastructure \
#     --admin-sa-name my-staging-kafka-admin \
#     [--output-dir  /path/to/output]
#
# Output:
#   Prints all values needed for .env and .tfvars files.
#   If --output-dir is specified, writes bootstrap-output.env to that directory.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
OUTPUT_DIR=""
ENVIRONMENT_ID=""
CLUSTER_ID=""
TF_SA_NAME=""
ADMIN_SA_NAME=""

# ── Parse arguments ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment)   ENVIRONMENT_ID="$2";  shift 2 ;;
    --cluster)       CLUSTER_ID="$2";      shift 2 ;;
    --tf-sa-name)    TF_SA_NAME="$2";      shift 2 ;;
    --admin-sa-name) ADMIN_SA_NAME="$2";   shift 2 ;;
    --output-dir)    OUTPUT_DIR="$2";       shift 2 ;;
    -h|--help)
      sed -n '2,/^$/{ s/^# //; s/^#//; p }' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Validate required arguments ───────────────────────────────────────────────
missing=()
[[ -z "$ENVIRONMENT_ID" ]] && missing+=("--environment")
[[ -z "$CLUSTER_ID" ]]     && missing+=("--cluster")
[[ -z "$TF_SA_NAME" ]]     && missing+=("--tf-sa-name")
[[ -z "$ADMIN_SA_NAME" ]]  && missing+=("--admin-sa-name")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: Missing required arguments: ${missing[*]}" >&2
  echo "Run with --help for usage." >&2
  exit 1
fi

# ── Verify prerequisites ─────────────────────────────────────────────────────
for cmd in confluent jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is required but not found in PATH" >&2
    exit 1
  fi
done

# ── Step 1: Operator login ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Confluent Cloud Bootstrap"
echo "  Environment: $ENVIRONMENT_ID  |  Cluster: $CLUSTER_ID"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "This script requires your personal Confluent Cloud login (email + password)."
echo "Your credentials are used only for this bootstrap session — Terraform will"
echo "authenticate with the service account API keys created below."
echo ""

# Check if already logged in
if ! confluent environment list --output json >/dev/null 2>&1; then
  echo "→ Logging in to Confluent Cloud..."
  confluent login --save
else
  echo "→ Already logged in to Confluent Cloud."
fi

# ── Step 2: Set environment ───────────────────────────────────────────────────
echo ""
echo "→ Setting environment to $ENVIRONMENT_ID..."
confluent environment use "$ENVIRONMENT_ID"

# ── Step 3: Retrieve Schema Registry info (via CLI) ──────────────────────────
# The CLI provides cluster ID and endpoint but NOT the CRN.
# We retrieve the authoritative CRN later via the REST API (Step 7b) once
# the Cloud API key is available.
echo ""
echo "→ Retrieving Schema Registry cluster info..."
SR_JSON=$(confluent schema-registry cluster describe --output json 2>/dev/null || echo "{}")

# CLI JSON uses 'cluster' not 'cluster_id'
SR_CLUSTER_ID=$(echo "$SR_JSON" | jq -r '.cluster // empty')
SR_ENDPOINT=$(echo "$SR_JSON" | jq -r '.endpoint_url // empty')
SR_CRN=""

if [[ -n "$SR_CLUSTER_ID" ]]; then
  echo "  SR Cluster ID: $SR_CLUSTER_ID"
  echo "  SR Endpoint:   $SR_ENDPOINT"
  echo "  SR CRN:        (retrieved after Cloud API key is created — Step 7b)"
else
  echo "  WARNING: Schema Registry not found or not enabled in this environment."
  echo "  SR fields will be empty — you can add them later if SR is enabled."
  SR_CLUSTER_ID=""
  SR_ENDPOINT=""
fi

# ── Step 4: Retrieve Kafka cluster endpoints ──────────────────────────────────
echo ""
echo "→ Retrieving Kafka cluster info for $CLUSTER_ID..."
confluent kafka cluster use "$CLUSTER_ID"
KAFKA_JSON=$(confluent kafka cluster describe --output json)

KAFKA_BOOTSTRAP=$(echo "$KAFKA_JSON" | jq -r '.endpoint // empty' | sed 's|SASL_SSL://||')
KAFKA_REST=$(echo "$KAFKA_JSON" | jq -r '.rest_endpoint // empty')

echo "  Bootstrap servers: $KAFKA_BOOTSTRAP"
echo "  REST endpoint:     $KAFKA_REST"

# ── Step 5: Create Terraform provider service account ─────────────────────────
echo ""
echo "→ Creating service account: $TF_SA_NAME..."

# Check if SA already exists
EXISTING_TF_SA=$(confluent iam service-account list --output json | jq -r ".[] | select(.name == \"$TF_SA_NAME\") | .id" 2>/dev/null || echo "")

if [[ -n "$EXISTING_TF_SA" ]]; then
  TF_SA_ID="$EXISTING_TF_SA"
  echo "  Already exists: $TF_SA_ID"
else
  TF_SA_JSON=$(confluent iam service-account create "$TF_SA_NAME" \
    --description "Terraform provider auth — manages service accounts, API keys, and role bindings" \
    --output json)
  TF_SA_ID=$(echo "$TF_SA_JSON" | jq -r '.id')
  echo "  Created: $TF_SA_ID"
fi

# ── Step 6: Assign EnvironmentAdmin role ──────────────────────────────────────
echo ""
echo "→ Assigning EnvironmentAdmin role to $TF_SA_NAME on $ENVIRONMENT_ID..."
confluent iam rbac role-binding create \
  --principal "User:$TF_SA_ID" \
  --role EnvironmentAdmin \
  --environment "$ENVIRONMENT_ID" 2>/dev/null \
  && echo "  Role binding created." \
  || echo "  Role binding may already exist (this is OK)."

# ── Step 7: Create Cloud API key for TF provider ─────────────────────────────
echo ""
echo "→ Creating Cloud API key for $TF_SA_NAME..."
CLOUD_KEY_JSON=$(confluent api-key create --resource cloud \
  --service-account "$TF_SA_ID" \
  --description "Cloud API key for Terraform provider ($TF_SA_NAME)" \
  --output json)

CLOUD_API_KEY=$(echo "$CLOUD_KEY_JSON" | jq -r '.api_key // .key')
CLOUD_API_SECRET=$(echo "$CLOUD_KEY_JSON" | jq -r '.api_secret // .secret')

echo "  Cloud API Key:    $CLOUD_API_KEY"
echo "  Cloud API Secret: (saved — not printed)"

# ── Step 7b: Retrieve SR CRN via REST API ─────────────────────────────────────
# The CLI does not return the CRN. The srcm/v3 REST API does, and requires
# a Cloud API key (which we just created). Brief propagation delay is possible.
if [[ -n "$SR_CLUSTER_ID" ]]; then
  echo ""
  echo "→ Retrieving Schema Registry CRN via REST API..."
  _sr_attempts=0
  while [[ $_sr_attempts -lt 3 ]]; do
    SR_API_JSON=$(curl -sS -u "$CLOUD_API_KEY:$CLOUD_API_SECRET" \
      "https://api.confluent.cloud/srcm/v3/clusters?environment=$ENVIRONMENT_ID" 2>/dev/null || echo "{}")

    SR_CRN=$(echo "$SR_API_JSON" | jq -r '.data[0].metadata.resource_name // empty' 2>/dev/null)

    if [[ -n "$SR_CRN" ]]; then
      echo "  SR CRN: $SR_CRN"
      break
    fi

    _sr_attempts=$((_sr_attempts + 1))
    if [[ $_sr_attempts -lt 3 ]]; then
      echo "  Waiting for Cloud API key propagation (attempt $_sr_attempts/3)..."
      sleep 5
    fi
  done

  if [[ -z "$SR_CRN" ]]; then
    echo "  WARNING: Could not retrieve SR CRN via REST API."
    echo "  You can retrieve it manually:"
    echo "    curl -sS -u '<cloud-api-key>:<secret>' 'https://api.confluent.cloud/srcm/v3/clusters?environment=$ENVIRONMENT_ID' | jq '.data[0].metadata.resource_name'"
  fi
fi

# ── Step 8: Create Kafka admin service account ────────────────────────────────
echo ""
echo "→ Creating service account: $ADMIN_SA_NAME..."

EXISTING_ADMIN_SA=$(confluent iam service-account list --output json | jq -r ".[] | select(.name == \"$ADMIN_SA_NAME\") | .id" 2>/dev/null || echo "")

if [[ -n "$EXISTING_ADMIN_SA" ]]; then
  ADMIN_SA_ID="$EXISTING_ADMIN_SA"
  echo "  Already exists: $ADMIN_SA_ID"
else
  ADMIN_SA_JSON=$(confluent iam service-account create "$ADMIN_SA_NAME" \
    --description "Kafka REST admin for Terraform topic/ACL management" \
    --output json)
  ADMIN_SA_ID=$(echo "$ADMIN_SA_JSON" | jq -r '.id')
  echo "  Created: $ADMIN_SA_ID"
fi

# ── Step 9: Create Cluster API key for Kafka admin ────────────────────────────
echo ""
echo "→ Creating Cluster API key for $ADMIN_SA_NAME on $CLUSTER_ID..."
CLUSTER_KEY_JSON=$(confluent api-key create --resource "$CLUSTER_ID" \
  --service-account "$ADMIN_SA_ID" \
  --description "Kafka REST admin key for Terraform topic/ACL management ($ADMIN_SA_NAME)" \
  --output json)

CLUSTER_API_KEY=$(echo "$CLUSTER_KEY_JSON" | jq -r '.api_key // .key')
CLUSTER_API_SECRET=$(echo "$CLUSTER_KEY_JSON" | jq -r '.api_secret // .secret')

echo "  Cluster API Key:    $CLUSTER_API_KEY"
echo "  Cluster API Secret: (saved — not printed)"

# ── Step 10: Grant cluster admin ACLs ─────────────────────────────────────────
echo ""
echo "→ Granting cluster admin ACLs to $ADMIN_SA_NAME ($ADMIN_SA_ID)..."

confluent kafka acl create --allow \
  --service-account "$ADMIN_SA_ID" \
  --operations read,write,create,delete,describe,describe-configs,alter,alter-configs \
  --topic '*' --cluster "$CLUSTER_ID" 2>&1 | sed 's/^/  /'

confluent kafka acl create --allow \
  --service-account "$ADMIN_SA_ID" \
  --operations read,write,create,delete,describe \
  --consumer-group '*' --cluster "$CLUSTER_ID" 2>&1 | sed 's/^/  /'

confluent kafka acl create --allow \
  --service-account "$ADMIN_SA_ID" \
  --operations describe,alter \
  --cluster-scope --cluster "$CLUSTER_ID" 2>&1 | sed 's/^/  /'

echo "  ACLs granted."

# ── Step 11: Verify Cloud API key ─────────────────────────────────────────────
echo ""
echo "→ Verifying Cloud API key..."
VERIFY_RESULT=$(curl -sS -o /dev/null -w "%{http_code}" \
  -u "$CLOUD_API_KEY:$CLOUD_API_SECRET" \
  "https://api.confluent.cloud/org/v2/organizations")

if [[ "$VERIFY_RESULT" == "200" ]]; then
  echo "  ✓ Cloud API key verified (HTTP 200)."
else
  echo "  ✗ Cloud API key verification failed (HTTP $VERIFY_RESULT)."
  echo "  This may indicate the key needs a few seconds to propagate. Retry shortly."
fi

# ── Output summary ────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "  Bootstrap Complete"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""
echo "── .env file values (Terraform provider auth) ──"
echo "CONFLUENT_CLOUD_API_KEY=$CLOUD_API_KEY"
echo "CONFLUENT_CLOUD_API_SECRET=$CLOUD_API_SECRET"
echo ""
echo "── .tfvars file values ──"
echo "environment_id          = \"$ENVIRONMENT_ID\""
echo "kafka_cluster_id        = \"$CLUSTER_ID\""
echo "kafka_rest_endpoint     = \"$KAFKA_REST\""
echo "kafka_bootstrap_servers = \"$KAFKA_BOOTSTRAP\""
echo "kafka_admin_credentials = {"
echo "  api_key    = \"$CLUSTER_API_KEY\""
echo "  api_secret = \"$CLUSTER_API_SECRET\""
echo "}"
if [[ -n "$SR_CLUSTER_ID" ]]; then
  echo "schema_registry = {"
  echo "  cluster_id    = \"$SR_CLUSTER_ID\""
  echo "  resource_name = \"$SR_CRN\""
  echo "  url           = \"$SR_ENDPOINT\""
  echo "}"
else
  echo "schema_registry = null"
fi
echo ""
echo "── Service accounts ──"
echo "$TF_SA_NAME    $TF_SA_ID"
echo "$ADMIN_SA_NAME $ADMIN_SA_ID"
echo ""
echo "── API key IDs (record in access registry — NOT the secrets) ──"
echo "Cloud API key:   $CLOUD_API_KEY  (owner: $TF_SA_NAME)"
echo "Cluster API key: $CLUSTER_API_KEY  (owner: $ADMIN_SA_NAME)"

# ── Optional: write output file ───────────────────────────────────────────────
if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  OUTPUT_FILE="$OUTPUT_DIR/bootstrap-output.env"
  cat > "$OUTPUT_FILE" <<EOF
# Generated by confluent-bootstrap.sh at $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Environment: $ENVIRONMENT_ID  Cluster: $CLUSTER_ID
#
# ── .env values ──
CONFLUENT_CLOUD_API_KEY=$CLOUD_API_KEY
CONFLUENT_CLOUD_API_SECRET=$CLOUD_API_SECRET
#
# ── .tfvars values ──
ENVIRONMENT_ID=$ENVIRONMENT_ID
KAFKA_CLUSTER_ID=$CLUSTER_ID
KAFKA_REST_ENDPOINT=$KAFKA_REST
KAFKA_BOOTSTRAP_SERVERS=$KAFKA_BOOTSTRAP
KAFKA_ADMIN_API_KEY=$CLUSTER_API_KEY
KAFKA_ADMIN_API_SECRET=$CLUSTER_API_SECRET
SR_CLUSTER_ID=$SR_CLUSTER_ID
SR_RESOURCE_NAME=$SR_CRN
SR_URL=$SR_ENDPOINT
#
# ── Service accounts ──
TF_SA_NAME=$TF_SA_NAME
TF_SA_ID=$TF_SA_ID
ADMIN_SA_NAME=$ADMIN_SA_NAME
ADMIN_SA_ID=$ADMIN_SA_ID
#
# ── API key IDs (for access registry) ──
CLOUD_API_KEY_ID=$CLOUD_API_KEY
CLUSTER_API_KEY_ID=$CLUSTER_API_KEY
EOF
  chmod 600 "$OUTPUT_FILE"
  echo "Output written to: $OUTPUT_FILE"
fi

echo ""
echo "Bootstrap complete. You can now log out of the Confluent CLI if desired:"
echo "  confluent logout"
