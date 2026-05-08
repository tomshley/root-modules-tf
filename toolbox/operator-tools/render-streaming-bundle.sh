#!/usr/bin/env bash
# render-streaming-bundle.sh — Render runtime credential bundles for streaming workloads.
#
# Reads Terraform/OpenTofu outputs from a stack directory and renders per-workload
# .env files with Kafka, Schema Registry, and Flink (Confluent Cloud) credentials.
#
# Usage:
#   ./render-streaming-bundle.sh [stack-dir]
#
# Arguments:
#   stack-dir  Path to the Terraform/OpenTofu stack directory (default: current directory).
#              Must contain a state with streaming outputs. Required: kafka_bootstrap_servers
#              and workload_kafka_api_key_ids. Optional: schema_registry_url, the five
#              flink_* scalars (flink_rest_endpoint, flink_compute_pool_id,
#              flink_runner_service_account_id, flink_environment_id, flink_organization_id),
#              and workload_flink_api_key_ids / _secrets — any missing optional outputs
#              are treated as empty and the corresponding blocks (or block lines) are
#              omitted per-workload.
#
# Output:
#   Creates <stack-dir>/.env-bundle/<workload>.env for each workload, composed
#   of up to three blocks in this order:
#   - KAFKA_BOOTSTRAP_SERVERS, KAFKA_API_KEY, KAFKA_API_SECRET
#       (when the workload has a Kafka API key in workload_kafka_api_key_ids)
#   - SCHEMA_REGISTRY_URL, SCHEMA_REGISTRY_API_KEY, SCHEMA_REGISTRY_API_SECRET
#       (when SR is configured and the workload has an SR API key)
#   - FLINK_PLATFORM, FLINK_REST_ENDPOINT, FLINK_COMPUTE_POOL_ID,
#     FLINK_RUNNER_SERVICE_ACCOUNT_ID, FLINK_ENVIRONMENT_ID,
#     FLINK_API_KEY, FLINK_API_SECRET
#       (when the workload has a Flink API key in workload_flink_api_key_ids).
#       Plus FLINK_ORGANIZATION_ID and FLINK_STATEMENTS_PATH (a pre-rendered
#       Flink Gateway REST path) when the stack additionally exposes a
#       flink_organization_id output, allowing curl + Basic-auth consumer
#       scripts to reach the statements collection without a vendor CLI or
#       a runtime URL-template builder.
#   A workload with only a Flink key renders a Flink-only env file; a workload
#   with no credentials in any map is skipped. All files are chmod 600.

set -euo pipefail
# Tighten default file/dir creation mode for the duration of this script so the
# OUTPUT_DIR (`.env-bundle/`) lands at 0700 and transient `: > "$env_file"`
# creations land at 0600 before any secrets are appended. The explicit `chmod 600`
# below is a belt-and-braces assertion; umask makes the pre-chmod window safe
# against same-host readers racing the renderer.
umask 077

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

# Flink-deploy SA outputs (present when a stack ships a Flink-only submit service
# account that needs the Confluent Cloud Flink REST API + compute-pool coordinates
# plus its own Flink API key pair, independent of any Kafka or Schema Registry
# access). Falls back to empty map / empty string when the stack has no such
# outputs, so pre-v1.8.6 stacks render their existing Kafka (+ optional SR)
# bundle unchanged.
#
# Coerce JSON/raw "null" to empty-map / empty-string. `tofu output -json` for an
# output that evaluates to null (e.g. `value = try(confluent_api_key.flink[0].id, null)`
# wrapping an optional resource) prints the literal `null` with exit 0, which would
# make `jq --argjson` downstream fail with "null and {} cannot be added" and short-circuit
# the whole renderer with a misleading "No workload credentials found" error. The `-raw`
# path can also surface the 4-char string "null" via the `make output` table-parser path
# that some consumer Makefiles wrap around tofu (see lib/render-helpers.sh::read_tf_output,
# v1.8.3).
FLINK_KEY_IDS=$($TOFU output -json workload_flink_api_key_ids 2>/dev/null || echo "{}")
FLINK_SECRETS=$($TOFU output -json workload_flink_api_secrets 2>/dev/null || echo "{}")
FLINK_REST_ENDPOINT=$($TOFU output -raw flink_rest_endpoint 2>/dev/null || echo "")
FLINK_COMPUTE_POOL_ID=$($TOFU output -raw flink_compute_pool_id 2>/dev/null || echo "")
FLINK_RUNNER_SA_ID=$($TOFU output -raw flink_runner_service_account_id 2>/dev/null || echo "")
FLINK_ENVIRONMENT_ID=$($TOFU output -raw flink_environment_id 2>/dev/null || echo "")
# Optional: organization id, used to pre-render the Flink Gateway REST statements
# path so consumer scripts don't have to bake the vendor URL template into per-service
# code. Stacks that don't expose this output get a Flink block without
# FLINK_ORGANIZATION_ID / FLINK_STATEMENTS_PATH, and the consumer must source the
# value (or the path) by other means.
FLINK_ORGANIZATION_ID=$($TOFU output -raw flink_organization_id 2>/dev/null || echo "")
[ "$FLINK_KEY_IDS" = "null" ] && FLINK_KEY_IDS="{}"
[ "$FLINK_SECRETS" = "null" ] && FLINK_SECRETS="{}"
[ "$FLINK_REST_ENDPOINT" = "null" ] && FLINK_REST_ENDPOINT=""
[ "$FLINK_COMPUTE_POOL_ID" = "null" ] && FLINK_COMPUTE_POOL_ID=""
[ "$FLINK_RUNNER_SA_ID" = "null" ] && FLINK_RUNNER_SA_ID=""
[ "$FLINK_ENVIRONMENT_ID" = "null" ] && FLINK_ENVIRONMENT_ID=""
[ "$FLINK_ORGANIZATION_ID" = "null" ] && FLINK_ORGANIZATION_ID=""

# Get workload names from the union of Kafka + Flink key maps.
# A workload in both maps renders both blocks (Kafka -> SR -> Flink order);
# a Flink-only workload renders only the Flink block.
WORKLOADS=$(jq -rn --argjson k "$KAFKA_KEY_IDS" --argjson f "$FLINK_KEY_IDS" '($k + $f) | keys[]' 2>/dev/null || true)

if [ -z "$WORKLOADS" ]; then
    echo "Error: No workload credentials found in Terraform outputs."
    echo "Verify that '$TOFU output -json workload_kafka_api_key_ids' or"
    echo "'$TOFU output -json workload_flink_api_key_ids' returns a non-empty"
    echo "map (the workload set is the union of both) and that jq is installed."
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Render .env files for each workload.
#
# Each block (Kafka / Schema Registry / Flink) is appended independently and only
# when the workload has a non-empty credential for that block. This avoids shipping
# empty KAFKA_API_KEY= / KAFKA_API_SECRET= lines for Flink-only workloads and avoids
# side effects between blocks (e.g. the previous write-then-truncate approach would
# silently erase an already-appended SR block when a workload lacked a Kafka key).
COUNT=0
SKIPPED=0
for workload in $WORKLOADS; do
    env_file="$OUTPUT_DIR/${workload}.env"

    KAFKA_KEY=$(echo "$KAFKA_KEY_IDS" | jq -r --arg w "$workload" '.[$w] // empty')
    KAFKA_SECRET=$(echo "$KAFKA_SECRETS" | jq -r --arg w "$workload" '.[$w] // empty')
    SR_KEY=$(echo "$SR_KEY_IDS" | jq -r --arg w "$workload" '.[$w] // empty')
    SR_SECRET=$(echo "$SR_SECRETS" | jq -r --arg w "$workload" '.[$w] // empty')
    FLINK_KEY=$(echo "$FLINK_KEY_IDS" | jq -r --arg w "$workload" '.[$w] // empty')
    FLINK_SECRET=$(echo "$FLINK_SECRETS" | jq -r --arg w "$workload" '.[$w] // empty')

    # Skip workloads with no credentials in any map. The union-of-keys set above
    # guarantees at least one of the six lookups resolves, but individual lookups
    # can still return empty (e.g. a map containing "foo": null).
    if [ -z "$KAFKA_KEY" ] && [ -z "$SR_KEY" ] && [ -z "$FLINK_KEY" ]; then
        echo "Skipped: $env_file (no credentials in Kafka/SR/Flink maps for workload '$workload')"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    # Start from a fresh, empty file; append blocks as credentials dictate.
    # umask 077 (set at script top) ensures the creation mode is 0600; the
    # explicit chmod is defensive against operators who override umask.
    : > "$env_file"
    chmod 600 "$env_file"
    has_content=0   # tracks whether any block has been appended yet, so
                    # block-to-block blank-line separators only fire between
                    # blocks (not as a leading blank line on SR-only or
                    # Flink-only files).

    # --- Kafka block ---
    if [ -n "$KAFKA_KEY" ]; then
        cat >> "$env_file" <<EOF
# Kafka connection
KAFKA_BOOTSTRAP_SERVERS=$KAFKA_BOOTSTRAP_SERVERS
KAFKA_API_KEY=$KAFKA_KEY
KAFKA_API_SECRET=$KAFKA_SECRET
EOF
        has_content=1
    fi

    # --- Schema Registry block ---
    # Requires both a cluster-level SR URL and a workload-level SR API key.
    if [ -n "$SCHEMA_REGISTRY_URL" ] && [ -n "$SR_KEY" ]; then
        [ "$has_content" = 1 ] && echo "" >> "$env_file"
        cat >> "$env_file" <<EOF
# Schema Registry
SCHEMA_REGISTRY_URL=$SCHEMA_REGISTRY_URL
SCHEMA_REGISTRY_API_KEY=$SR_KEY
SCHEMA_REGISTRY_API_SECRET=$SR_SECRET
EOF
        has_content=1
    fi

    # --- Flink block (Confluent Cloud) ---
    # Rendered when the workload has a Flink API key (e.g. a Flink-only submit
    # service account that ships only `workload_flink_api_*` outputs).
    # Coexists with Kafka+SR blocks when a workload appears in multiple maps.
    #
    # FLINK_PLATFORM is a discriminator the consumer script switches on to pick
    # the right request-body shape. Today the renderer only knows the Confluent
    # Cloud Flink Gateway and emits the literal `confluent_cloud`; future
    # platforms (e.g. Apache Flink SQL Gateway, Ververica Platform) would extend
    # this with a corresponding TF input and a different value.
    #
    # FLINK_STATEMENTS_PATH is the Flink Gateway path tail that consumers append
    # to FLINK_REST_ENDPOINT to reach the statements collection. The Confluent
    # Cloud Flink Gateway embeds the org and environment IDs in the path
    # (https://docs.confluent.io/cloud/current/flink/operate-and-deploy/flink-rest-api.html);
    # pre-rendering it here keeps the URL template out of per-consumer scripts
    # and lets a curl + Basic-auth consumer talk to the gateway without a
    # vendor CLI dependency. Emitted only when the stack exposes the optional
    # flink_organization_id output AND a flink_environment_id; otherwise the
    # path lines are omitted and the consumer is expected to fail loudly
    # rather than fall back to a malformed URL.
    if [ -n "$FLINK_KEY" ]; then
        [ "$has_content" = 1 ] && echo "" >> "$env_file"
        cat >> "$env_file" <<EOF
# Flink (Confluent Cloud)
FLINK_PLATFORM=confluent_cloud
FLINK_REST_ENDPOINT=$FLINK_REST_ENDPOINT
FLINK_COMPUTE_POOL_ID=$FLINK_COMPUTE_POOL_ID
FLINK_RUNNER_SERVICE_ACCOUNT_ID=$FLINK_RUNNER_SA_ID
FLINK_ENVIRONMENT_ID=$FLINK_ENVIRONMENT_ID
FLINK_API_KEY=$FLINK_KEY
FLINK_API_SECRET=$FLINK_SECRET
EOF
        if [ -n "$FLINK_ORGANIZATION_ID" ] && [ -n "$FLINK_ENVIRONMENT_ID" ]; then
            cat >> "$env_file" <<EOF
FLINK_ORGANIZATION_ID=$FLINK_ORGANIZATION_ID
FLINK_STATEMENTS_PATH=/sql/v1/organizations/$FLINK_ORGANIZATION_ID/environments/$FLINK_ENVIRONMENT_ID/statements
EOF
        fi
    fi

    echo "Created: $env_file"
    COUNT=$((COUNT + 1))
done

echo "Bundle rendered to: $OUTPUT_DIR"
echo "Files created: $COUNT"
if [ "$SKIPPED" -gt 0 ]; then
    echo "Files skipped: $SKIPPED (workloads with no credentials)"
fi
