#!/usr/bin/env bash
# render-helpers.sh - Sourceable bash library for credential bundle rendering.
#
# Provides reusable helpers for consumer-side render scripts that need to:
#   - Read OpenTofu/Terraform stack outputs
#   - Resolve AWS Secrets Manager secret values
#   - Download the Amazon RDS root CA bundle
#   - Write secured (chmod 600) .env files
#
# This library is intentionally low-level: it does NOT know about specific
# services, bundles, or output names. Consumers compose these helpers in
# per-service render scripts that they own and maintain.
#
# USAGE
#   source "${OPERATOR_TOOLS}/lib/render-helpers.sh"
#
#   # at the top of a per-service render script:
#   require_command jq curl aws
#   init_render_counters
#
#   # then compose:
#   CLUSTER=$(read_tf_output_required "$CLOUD_DIR" cluster_name "cloud")
#   write_file_secure "$OUT/deploy.env" 600 <<EOF
#   AWS_REGION=$REGION
#   K8S_CLUSTER_NAME=$CLUSTER
#   EOF
#   emit_ok "deploy.env"
#
#   print_render_summary
#
# DESIGN
#   Functions are intentionally side-effect light. Output goes to stdout
#   (for value-returning functions) or stderr (for log/error messages).
#   Counter mutations use globals OK_COUNT and SKIP_COUNT which the caller
#   initialises via init_render_counters.
#
# REQUIREMENTS
#   bash >= 4 (for `local -n` not used; `set -u` safe)
#   tofu (or terraform — set TOFU env var to override)
#   jq, curl, aws CLI

# Note: Do NOT enable `set -e` here -- this file is sourced. Callers control
# their own shell options. Functions return non-zero on error and use the
# emit_* helpers to log.

TOFU="${TOFU:-tofu}"
RDS_CA_URL_DEFAULT="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"

# ========================================================================
# Counters and logging
# ========================================================================

# Initialise render counters. Callers should invoke this once at the top
# of their script before any emit_* calls.
init_render_counters() {
  OK_COUNT=0
  SKIP_COUNT=0
}

# emit_ok FILENAME
#   Increment OK counter and print a success line.
emit_ok() {
  local file="$1"
  OK_COUNT=$((OK_COUNT + 1))
  echo "  ✓ $(basename "$file")"
}

# emit_skip MESSAGE
#   Increment SKIP counter and print a warning to stderr.
emit_skip() {
  local msg="$1"
  SKIP_COUNT=$((SKIP_COUNT + 1))
  echo "  ⊘ $msg" >&2
}

# emit_info MESSAGE
#   Print an informational line (no counter mutation).
emit_info() {
  echo "  ⓘ $1"
}

# print_render_summary
#   Print the standard end-of-script summary line.
print_render_summary() {
  echo ""
  echo "Done: ${OK_COUNT:-0} rendered, ${SKIP_COUNT:-0} skipped"
}

# ========================================================================
# Validation helpers
# ========================================================================

# require_command CMD [CMD...]
#   Exit 1 if any command is missing from PATH.
require_command() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: $cmd is required but not found in PATH" >&2
      exit 1
    fi
  done
}

# require_directory DIR [LABEL]
#   Exit 1 if DIR is not an existing directory.
require_directory() {
  local dir="$1" label="${2:-stack}"
  if [[ ! -d "$dir" ]]; then
    echo "Error: $label directory not found: $dir" >&2
    exit 1
  fi
}

# require_env_var VAR_NAME [LABEL]
#   Exit 1 if the named environment variable is unset or empty.
require_env_var() {
  local name="$1" label="${2:-$1}"
  if [[ -z "${!name:-}" ]]; then
    echo "Error: $label is required (set $name)" >&2
    exit 1
  fi
}

# ========================================================================
# OpenTofu/Terraform output helpers
# ========================================================================

# read_tf_output STACK_DIR KEY
#   Echo the raw value of a single TF output, or empty string on failure.
#   Tries `make output` first (consumers commonly wrap tofu via Makefile)
#   and falls back to `tofu output -raw`.
#   Coerces literal string "null" to empty (TF null outputs render as the
#   4-char string "null" via make output but as empty via tofu -raw).
read_tf_output() {
  local dir="$1" key="$2" val=""
  val=$(cd "$dir" && make output 2>/dev/null \
    | grep -E "^${key}\\s" \
    | sed 's/.*= *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "")
  if [[ -z "$val" ]]; then
    val=$(cd "$dir" && $TOFU output -raw "$key" 2>/dev/null || echo "")
  fi
  if [[ "$val" == "null" ]]; then
    val=""
  fi
  echo "$val"
}

# read_tf_output_required STACK_DIR KEY [STACK_LABEL]
#   Echo the value, or print an error and exit 1 if empty.
#   STACK_LABEL is used in the error message (defaults to the dir basename).
read_tf_output_required() {
  local dir="$1" key="$2" label="${3:-$(basename "$1")}" val
  val=$(read_tf_output "$dir" "$key")
  if [[ -z "$val" ]]; then
    echo "Error: $key output is empty or missing from $label stack." >&2
    echo "Has the stack been applied? Run: make -C $dir output" >&2
    exit 1
  fi
  echo "$val"
}

# read_tf_output_json STACK_DIR KEY
#   Echo the JSON value of an output (object/array), or "{}" on failure.
read_tf_output_json() {
  local dir="$1" key="$2"
  (cd "$dir" && $TOFU output -json "$key" 2>/dev/null) || echo "{}"
}

# read_tf_output_map_value STACK_DIR KEY MAP_KEY
#   For an output that is a map(string), echo the value of map[MAP_KEY],
#   or empty if the key is absent.
read_tf_output_map_value() {
  local dir="$1" key="$2" map_key="$3"
  read_tf_output_json "$dir" "$key" | jq -r --arg k "$map_key" '.[$k] // empty'
}

# ========================================================================
# AWS Secrets Manager helpers
# ========================================================================

# get_secret_string SECRET_ARN REGION
#   Echo the raw SecretString, or empty string on failure (network, IAM,
#   secret-without-version, etc).
get_secret_string() {
  local arn="$1" region="$2"
  aws secretsmanager get-secret-value \
    --secret-id "$arn" --region "$region" \
    --query SecretString --output text 2>/dev/null || echo ""
}

# get_secret_field SECRET_ARN REGION FIELD
#   Echo the value of .FIELD inside the SecretString JSON, or empty on
#   any failure.
get_secret_field() {
  local arn="$1" region="$2" field="$3"
  local json
  json=$(get_secret_string "$arn" "$region")
  if [[ -z "$json" ]]; then
    echo ""
    return
  fi
  echo "$json" | jq -r --arg f "$field" '.[$f] // empty'
}

# ========================================================================
# File writers
# ========================================================================

# write_file_secure PATH MODE
#   Read stdin, write to PATH, then chmod MODE.
#   Creates parent directory if needed.
write_file_secure() {
  local path="$1" mode="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  chmod "$mode" "$path"
}

# download_rds_ca_bundle OUTFILE [URL]
#   Download Amazon RDS root CA bundle to OUTFILE, chmod 600.
#   Returns 0 on success, non-zero on failure (caller decides whether to
#   emit_skip or fail hard).
download_rds_ca_bundle() {
  local outfile="$1" url="${2:-$RDS_CA_URL_DEFAULT}"
  if curl -sfL "$url" -o "$outfile"; then
    chmod 600 "$outfile"
    return 0
  fi
  return 1
}
