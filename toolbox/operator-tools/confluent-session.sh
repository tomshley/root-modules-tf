#!/usr/bin/env bash
# confluent-session.sh — Source this file to load Confluent Cloud credentials from an env file.
#
# Usage:
#   source /path/to/operator-tools/confluent-session.sh /path/to/.secure_files/staging-us-east-1-streaming.env
#
# This sources the specified env file (KEY=value format), exports Confluent CLI
# credentials, then verifies connectivity with the Confluent CLI if available.
#
# The env file must define: CONFLUENT_CLOUD_API_KEY, CONFLUENT_CLOUD_API_SECRET.

# Save caller's shell options so sourcing does not contaminate the calling shell
_confluent_session_oldopts="$(set +o); $(shopt -po 2>/dev/null || true)"
set -euo pipefail

ENV_FILE="${1:?Usage: source confluent-session.sh <env-file-path>}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found" >&2
  eval "$_confluent_session_oldopts" 2>/dev/null || true
  unset _confluent_session_oldopts
  return 1 2>/dev/null || exit 1
fi

# Load Confluent credentials from env file (KEY=value format)
while IFS= read -r line; do
  if [[ $line =~ ^CONFLUENT_CLOUD_API_KEY= ]]; then
    _val="${line#*=}"
    _val="${_val#\"}"; _val="${_val%\"}"
    _val="${_val#\'}"  ; _val="${_val%\'}"
    export CONFLUENT_CLOUD_API_KEY="$_val"
  elif [[ $line =~ ^CONFLUENT_CLOUD_API_SECRET= ]]; then
    _val="${line#*=}"
    _val="${_val#\"}"; _val="${_val%\"}"
    _val="${_val#\'}"  ; _val="${_val%\'}"
    export CONFLUENT_CLOUD_API_SECRET="$_val"
  fi
done < "$ENV_FILE"

if [[ -z "${CONFLUENT_CLOUD_API_KEY:-}" || -z "${CONFLUENT_CLOUD_API_SECRET:-}" ]]; then
  echo "ERROR: Required Confluent credentials not found in $ENV_FILE" >&2
  echo "Expected: CONFLUENT_CLOUD_API_KEY, CONFLUENT_CLOUD_API_SECRET" >&2
  eval "$_confluent_session_oldopts" 2>/dev/null || true
  unset _confluent_session_oldopts
  return 1 2>/dev/null || exit 1
fi

echo "Loaded Confluent env from: ${ENV_FILE}"

# Verify connectivity if Confluent CLI is available
if command -v confluent >/dev/null 2>&1; then
  echo "Verifying Confluent connectivity..."
  confluent environment list --output json >/dev/null || echo "Warning: Could not verify Confluent connectivity"
else
  echo "Confluent CLI not found - skipping connectivity check"
fi

# Restore caller's shell options
eval "$_confluent_session_oldopts" 2>/dev/null || true
unset _confluent_session_oldopts
