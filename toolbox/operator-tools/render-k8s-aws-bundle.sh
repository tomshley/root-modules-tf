#!/usr/bin/env bash
# render-k8s-aws-bundle.sh — Render per-service AWS resource .env files from Terraform outputs.
#
# Reads Terraform/OpenTofu outputs from cloud, data, and (optionally) tls stack
# directories and renders a shell-sourceable .env file with the exact variable
# names expected by CI deploy jobs in consumer service repos.
#
# Usage:
#   ./render-k8s-aws-bundle.sh --service <ingress|readserver|structuring> \
#     --cloud-dir <path> --data-dir <path> [--tls-dir <path>]
#
# Arguments:
#   --service     Required. One of: ingress, readserver, structuring.
#   --cloud-dir   Required. Path to the cloud stack directory (karpenter_node_role_name).
#   --data-dir    Required. Path to the data stack directory (ingress_irsa_role_arn,
#                 readserver_irsa_role_arn, or structuring_irsa_role_arn).
#   --tls-dir     Optional. Path to the tls stack directory (certificate_arn or
#                 api_certificate_arn). Required for ingress and readserver.
#
# Output:
#   Creates <cloud-dir>/.env-bundle/<service>-k8s-aws.env with the variables
#   expected by the CI deploy job's `source` + `sed` placeholder substitution.
#   File is chmod 600.
#
# Variable contract (must match CI .gitlab-ci.yml):
#   ingress:      ACM_CERT_ARN, IRSA_ROLE_ARN, KARPENTER_NODE_ROLE
#   readserver:   ACM_CERT_ARN, IRSA_ROLE_ARN, KARPENTER_NODE_ROLE
#   structuring:  IRSA_ROLE_ARN, KARPENTER_NODE_ROLE

set -euo pipefail

TOFU="${TOFU:-tofu}"

# --- Parse arguments ---
SERVICE=""
CLOUD_DIR=""
DATA_DIR=""
TLS_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service)    SERVICE="$2";    shift 2 ;;
    --cloud-dir)  CLOUD_DIR="$2";  shift 2 ;;
    --data-dir)   DATA_DIR="$2";   shift 2 ;;
    --tls-dir)    TLS_DIR="$2";    shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --service <ingress|readserver|structuring> --cloud-dir <path> --data-dir <path> [--tls-dir <path>]" >&2
      exit 1
      ;;
  esac
done

# --- Validate arguments ---
if [[ -z "$SERVICE" ]]; then
  echo "Error: --service is required (ingress, readserver, or structuring)" >&2; exit 1
fi
if [[ "$SERVICE" != "ingress" && "$SERVICE" != "readserver" && "$SERVICE" != "structuring" ]]; then
  echo "Error: --service must be 'ingress', 'readserver', or 'structuring', got '$SERVICE'" >&2; exit 1
fi
if [[ -z "$CLOUD_DIR" ]]; then
  echo "Error: --cloud-dir is required" >&2; exit 1
fi
if [[ -z "$DATA_DIR" ]]; then
  echo "Error: --data-dir is required" >&2; exit 1
fi
if [[ ("$SERVICE" == "ingress" || "$SERVICE" == "readserver") && -z "$TLS_DIR" ]]; then
  echo "Error: --tls-dir is required for $SERVICE service (ACM certificate)" >&2; exit 1
fi

echo "Rendering $SERVICE k8s-aws bundle"
echo "  cloud-dir: $CLOUD_DIR"
echo "  data-dir:  $DATA_DIR"
[[ -n "$TLS_DIR" ]] && echo "  tls-dir:   $TLS_DIR"

# --- Read cloud stack outputs ---
KARPENTER_NODE_ROLE=$(cd "$CLOUD_DIR" && make output 2>/dev/null | grep 'karpenter_node_role_name' | sed 's/.*= *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "")
if [[ -z "$KARPENTER_NODE_ROLE" ]]; then
  # Fallback: try tofu output directly if make output didn't work
  KARPENTER_NODE_ROLE=$(cd "$CLOUD_DIR" && $TOFU output -raw karpenter_node_role_name 2>/dev/null || echo "")
fi
if [[ -z "$KARPENTER_NODE_ROLE" ]]; then
  echo "Error: karpenter_node_role_name output is empty or missing from cloud stack." >&2
  echo "Has the cloud stack been applied? Run: make -C $CLOUD_DIR output" >&2
  exit 1
fi
echo "  KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE"

# --- Read data stack outputs ---
case "$SERVICE" in
  ingress)     IRSA_OUTPUT_NAME="ingress_irsa_role_arn" ;;
  readserver)  IRSA_OUTPUT_NAME="readserver_irsa_role_arn" ;;
  structuring) IRSA_OUTPUT_NAME="structuring_irsa_role_arn" ;;
esac

IRSA_ROLE_ARN=$(cd "$DATA_DIR" && make output 2>/dev/null | grep "$IRSA_OUTPUT_NAME" | sed 's/.*= *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "")
if [[ -z "$IRSA_ROLE_ARN" ]]; then
  IRSA_ROLE_ARN=$(cd "$DATA_DIR" && $TOFU output -raw "$IRSA_OUTPUT_NAME" 2>/dev/null || echo "")
fi
if [[ -z "$IRSA_ROLE_ARN" ]]; then
  echo "Error: $IRSA_OUTPUT_NAME output is empty or missing from data stack." >&2
  echo "Has the data stack been applied? Run: make -C $DATA_DIR output" >&2
  exit 1
fi
echo "  IRSA_ROLE_ARN=$IRSA_ROLE_ARN"

# --- Read tls stack outputs (ingress and readserver) ---
ACM_CERT_ARN=""
if [[ ("$SERVICE" == "ingress" || "$SERVICE" == "readserver") && -n "$TLS_DIR" ]]; then
  # ingress uses certificate_arn; readserver uses api_certificate_arn
  if [[ "$SERVICE" == "readserver" ]]; then
    TLS_OUTPUT_NAME="api_certificate_arn"
  else
    TLS_OUTPUT_NAME="certificate_arn"
  fi
  ACM_CERT_ARN=$(cd "$TLS_DIR" && make output 2>/dev/null | grep "^${TLS_OUTPUT_NAME} " | head -1 | sed 's/.*= *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "")
  if [[ -z "$ACM_CERT_ARN" ]]; then
    ACM_CERT_ARN=$(cd "$TLS_DIR" && $TOFU output -raw "$TLS_OUTPUT_NAME" 2>/dev/null || echo "")
  fi
  if [[ -z "$ACM_CERT_ARN" ]]; then
    echo "Error: $TLS_OUTPUT_NAME output is empty or missing from tls stack." >&2
    echo "Has the tls stack been applied? Run: make -C $TLS_DIR output" >&2
    exit 1
  fi
  echo "  ACM_CERT_ARN=$ACM_CERT_ARN"
fi

# --- Render .env file ---
OUTPUT_DIR="$CLOUD_DIR/.env-bundle"
mkdir -p "$OUTPUT_DIR"
ENV_FILE="$OUTPUT_DIR/${SERVICE}-k8s-aws.env"

case "$SERVICE" in
  ingress)
    cat > "$ENV_FILE" <<EOF
# AWS resource ARNs and Karpenter node role for ingress
# Rendered by render-k8s-aws-bundle.sh from tls, data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
ACM_CERT_ARN=$ACM_CERT_ARN
IRSA_ROLE_ARN=$IRSA_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
    ;;
  readserver)
    cat > "$ENV_FILE" <<EOF
# AWS resource ARNs and Karpenter node role for readserver
# Rendered by render-k8s-aws-bundle.sh from tls, data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
ACM_CERT_ARN=$ACM_CERT_ARN
IRSA_ROLE_ARN=$IRSA_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
    ;;
  structuring)
    cat > "$ENV_FILE" <<EOF
# IRSA role ARN and Karpenter node role for structuring
# Rendered by render-k8s-aws-bundle.sh from data, cloud stack outputs
# Variable names must match CI deploy job placeholder substitution
IRSA_ROLE_ARN=$IRSA_ROLE_ARN
KARPENTER_NODE_ROLE=$KARPENTER_NODE_ROLE
EOF
    ;;
esac

chmod 600 "$ENV_FILE"

echo ""
echo "Created: $ENV_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the file: cat $ENV_FILE"
echo "  2. Copy to consumer project .secure_files/ as <env>-k8s-aws.env"
echo "  3. Upload to GitLab Secure Files in the consumer project"
