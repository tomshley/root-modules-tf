#!/usr/bin/env bash
# aws-session.sh — Source this file to load AWS credentials from an env file.
#
# Usage:
#   source /path/to/operator-tools/aws-session.sh /path/to/.secure_files/staging-us-east-1-cloud.env
#
# This sources the specified env file (KEY=value format), unsets AWS_PROFILE
# and AWS_SESSION_TOKEN so that static IAM credentials take effect, then
# verifies connectivity with `aws sts get-caller-identity`.
#
# The env file must define: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# AWS_DEFAULT_REGION (or AWS_REGION).

# Save caller's shell options so sourcing does not contaminate the calling shell
_aws_session_oldopts="$(set +o); $(shopt -po 2>/dev/null || true)"
set -euo pipefail

ENV_FILE="${1:?Usage: source aws-session.sh <env-file-path>}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found" >&2
  eval "$_aws_session_oldopts" 2>/dev/null || true
  unset _aws_session_oldopts
  return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# Static IAM credentials — clear profile/session so they don't override
unset AWS_PROFILE 2>/dev/null || true
unset AWS_SESSION_TOKEN 2>/dev/null || true

export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION AWS_REGION

echo "Loaded AWS env from: ${ENV_FILE}"
aws sts get-caller-identity

# Restore caller's shell options
eval "$_aws_session_oldopts" 2>/dev/null || true
unset _aws_session_oldopts
