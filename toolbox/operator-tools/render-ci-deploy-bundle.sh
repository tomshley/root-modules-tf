#!/usr/bin/env bash
# render-ci-deploy-bundle.sh — Render CI deploy credential bundle from cloud stack outputs.
#
# Reads Terraform/OpenTofu outputs from a cloud stack directory and renders
# a deploy .env file with the OIDC role ARN and cluster details needed by
# consumer CI pipelines (e.g. your-ingress-service).
#
# Usage:
#   ./render-ci-deploy-bundle.sh [stack-dir] [namespace]
#
# Arguments:
#   stack-dir   Path to the cloud stack directory (default: current directory).
#               Must contain a state with cloud outputs (cluster_name,
#               ci_deploy_role_arn, etc.).
#   namespace   Kubernetes namespace for the deploy target (default: none).
#
# Output:
#   Creates <stack-dir>/.env-bundle/ci-deploy.env with:
#   - AWS_DEFAULT_REGION, AWS_REGION
#   - K8S_CLUSTER_NAME
#   - CI_DEPLOY_ROLE_ARN
#   - K8S_NAMESPACE (when provided)
#   File is chmod 600.
#
# The rendered file is intended to be uploaded to GitLab Secure Files in the
# consumer project as staging-k8s-deploy.env (or similar).

set -euo pipefail

TOFU="${TOFU:-tofu}"

# Default to current directory if not specified
STACK_DIR="${1:-$(pwd)}"
K8S_NAMESPACE="${2:-}"
OUTPUT_DIR="$STACK_DIR/.env-bundle"

echo "Rendering CI deploy bundle for stack: $STACK_DIR"

# Read outputs from the cloud stack
cd "$STACK_DIR"

CLUSTER_NAME=$($TOFU output -raw cluster_name 2>/dev/null || echo "")
if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: cluster_name output is empty or missing. Has the cloud stack been applied?" >&2
    exit 1
fi

CI_DEPLOY_ROLE_ARN=$($TOFU output -raw ci_deploy_role_arn 2>/dev/null || echo "")
if [ -z "$CI_DEPLOY_ROLE_ARN" ] || [ "$CI_DEPLOY_ROLE_ARN" = "null" ]; then
    echo "Error: ci_deploy_role_arn output is empty or null." >&2
    echo "Ensure ci_oidc_access is configured in the cloud stack tfvars and the stack has been applied." >&2
    exit 1
fi

# Derive region from the cluster name convention: <project>-<env>-<region>
# Fall back to AWS_REGION or us-east-1
AWS_REGION="${AWS_REGION:-}"
if [ -z "$AWS_REGION" ]; then
    # Try to extract region from cluster name (e.g. myapp-staging-us-east-1)
    AWS_REGION=$(echo "$CLUSTER_NAME" | grep -oE '(us|eu|ap|sa|ca|me|af)-(east|west|north|south|central|northeast|southeast|southwest)-[0-9]+' || echo "us-east-1")
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

ENV_FILE="$OUTPUT_DIR/ci-deploy.env"

cat > "$ENV_FILE" <<EOF
# CI deploy credentials — rendered by render-ci-deploy-bundle.sh
# Upload to GitLab Secure Files in consumer projects as staging-k8s-deploy.env
# See your-infra-repo/docs/ci-oidc-setup.md
AWS_DEFAULT_REGION=$AWS_REGION
AWS_REGION=$AWS_REGION
K8S_CLUSTER_NAME=$CLUSTER_NAME
CI_DEPLOY_ROLE_ARN=$CI_DEPLOY_ROLE_ARN
EOF

if [ -n "$K8S_NAMESPACE" ]; then
    echo "K8S_NAMESPACE=$K8S_NAMESPACE" >> "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"

echo "Created: $ENV_FILE"
echo ""
echo "Next steps:"
echo "  1. Review the file: cat $ENV_FILE"
echo "  2. Copy to consumer project .secure_files/ (add K8S_NAMESPACE if not set)"
echo "  3. Upload to GitLab Secure Files in the consumer project"
echo "  4. Ensure the consumer CI pipeline uses id_tokens + assume-role-with-web-identity"
