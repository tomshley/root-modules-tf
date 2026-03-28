#!/usr/bin/env bash
# render-streaming-bundle.sh — Render runtime credential bundles for streaming workloads.
#
# Reads Terraform/OpenTofu outputs from a stack directory and renders per-workload
# .env files with Kafka and Schema Registry credentials.
#
# Usage:
#   ./render-streaming-bundle.sh [stack-dir]
#
# Arguments:
#   stack-dir  Path to the Terraform/OpenTofu stack directory (default: current directory).
#              Must contain a state with streaming outputs (kafka_bootstrap_servers,
#              workload_kafka_api_key_ids, etc.).
#
# Output:
#   Creates <stack-dir>/.env-bundle/<workload>.env for each workload with:
#   - KAFKA_BOOTSTRAP_SERVERS, KAFKA_API_KEY, KAFKA_API_SECRET
#   - SCHEMA_REGISTRY_URL, SCHEMA_REGISTRY_API_KEY, SCHEMA_REGISTRY_API_SECRET (when configured)
#   All files are chmod 600.

set -euo pipefail

TOFU="${TOFU:-tofu}"

# Default to current directory if not specified
STACK_DIR="${1:-$(pwd)}"
OUTPUT_DIR="$STACK_DIR/.env-bundle"

echo "Rendering streaming credential bundles for stack: $STACK_DIR"

# Check if stack is configured for streaming
cd "$STACK_DIR"

if ! $TOFU output confluent_configured 2>/dev/null | grep -q "true"; then
    echo "Streaming not configured (confluent_configured = false). Exiting cleanly."
    exit 0
fi

# Read shared connection outputs
KAFKA_BOOTSTRAP_SERVERS=$($TOFU output -raw kafka_bootstrap_servers 2>/dev/null || echo "")
SCHEMA_REGISTRY_URL=$($TOFU output -raw schema_registry_url 2>/dev/null || echo "")

if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ]; then
    echo "Error: kafka_bootstrap_servers output is empty or missing"
    exit 1
fi

# Read all workload credential maps as JSON (single tofu call per output)
KAFKA_KEY_IDS=$($TOFU output -json workload_kafka_api_key_ids 2>/dev/null || echo "{}")
KAFKA_SECRETS=$($TOFU output -json workload_kafka_api_secrets 2>/dev/null || echo "{}")
SR_KEY_IDS=$($TOFU output -json workload_schema_registry_api_key_ids 2>/dev/null || echo "{}")
SR_SECRETS=$($TOFU output -json workload_schema_registry_api_secrets 2>/dev/null || echo "{}")

# Get workload names from the key IDs map
WORKLOADS=$(echo "$KAFKA_KEY_IDS" | jq -r 'keys[]' 2>/dev/null || true)

if [ -z "$WORKLOADS" ]; then
    echo "Error: No workload credentials found in Terraform outputs."
    echo "Verify that '$TOFU output -json workload_kafka_api_key_ids' returns data and that jq is installed."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Render .env files for each workload
COUNT=0
for workload in $WORKLOADS; do
    env_file="$OUTPUT_DIR/${workload}.env"

    KAFKA_KEY=$(echo "$KAFKA_KEY_IDS" | jq -r --arg w "$workload" '.[$w] // empty')
    KAFKA_SECRET=$(echo "$KAFKA_SECRETS" | jq -r --arg w "$workload" '.[$w] // empty')

    cat > "$env_file" <<EOF
# Kafka connection
KAFKA_BOOTSTRAP_SERVERS=$KAFKA_BOOTSTRAP_SERVERS
KAFKA_API_KEY=$KAFKA_KEY
KAFKA_API_SECRET=$KAFKA_SECRET
EOF

    # Add Schema Registry credentials if configured
    if [ -n "$SCHEMA_REGISTRY_URL" ]; then
        SR_KEY=$(echo "$SR_KEY_IDS" | jq -r --arg w "$workload" '.[$w] // empty')
        SR_SECRET=$(echo "$SR_SECRETS" | jq -r --arg w "$workload" '.[$w] // empty')

        if [ -n "$SR_KEY" ]; then
            cat >> "$env_file" <<EOF

# Schema Registry
SCHEMA_REGISTRY_URL=$SCHEMA_REGISTRY_URL
SCHEMA_REGISTRY_API_KEY=$SR_KEY
SCHEMA_REGISTRY_API_SECRET=$SR_SECRET
EOF
        fi
    fi

    chmod 600 "$env_file"
    echo "Created: $env_file"
    COUNT=$((COUNT + 1))
done

echo "Bundle rendered to: $OUTPUT_DIR"
echo "Files created: $COUNT"
