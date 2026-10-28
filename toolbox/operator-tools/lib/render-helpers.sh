#!/usr/bin/env bash
# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# render-helpers.sh - Sourceable bash library for credential bundle rendering.
#
# Provides reusable helpers for consumer-side render scripts that need to:
#   - Read OpenTofu/Terraform stack outputs
#   - Resolve AWS Secrets Manager / GCP Secret Manager secret values
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
#   jq, curl, aws CLI (AWS bundles), gcloud CLI (GCP bundles)

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
#   and falls back to `tofu output -json` for the single key. The JSON form
#   matters: `tofu output -raw` prints a "No outputs found" warning on
#   stdout and still exits 0 in a directory whose state holds no outputs,
#   so its text looked like a real value here and silently rendered into
#   .env files. `-json` prints nothing and exits 1 in that case, which is
#   the honest empty signal. Strings come back unquoted to match -raw; a
#   non-string value comes back as compact JSON.
#   Coerces the literal string "null" to empty: `make output` grep of a
#   `key = value` table returns the 4-char string "null" for TF null
#   outputs, whereas `tofu output -json` returns JSON null (normalised to
#   empty by the jq below). Without this normalisation, caller-side guards
#   like `if [[ -n "$val" ]]` would treat "null" as a populated value and
#   emit `KEY=null` into `.env` files instead of omitting the line.
read_tf_output() {
  local dir="$1" key="$2" val=""
  val=$(cd "$dir" && make output 2>/dev/null \
    | grep -E "^${key}\\s" \
    | awk -F'= ' '{print $2}' | tr -d '"' | tr -d ' ')
  # `make output` redacts sensitive outputs ("<sensitive>" or "(sensitive
  # value)" — spaces stripped above). A redaction marker is not a value:
  # treat it as empty so the -json fallback reads the real value.
  case "$val" in
    "<sensitive>"|"(sensitivevalue)") val="" ;;
  esac
  if [[ -z "$val" ]]; then
    local raw
    if raw=$(cd "$dir" && $TOFU output -json "$key" 2>/dev/null); then
      val=$(printf '%s' "$raw" | jq -r 'if . == null then "" elif type == "string" then . else tojson end')
    else
      val=""
    fi
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
#   Tries raw tofu first (CI exports TF_HTTP_USERNAME/PASSWORD directly).
#   Falls back to replaying the command through the consumer Makefile via a
#   stdin-injected target: after the credential-transport hardening the HTTP
#   backend username/password live ONLY in the Makefile's exported env (no
#   longer persisted in .terraform/ backend metadata by -backend-config
#   args), so raw tofu outside make cannot read state. Without this fallback
#   the old silent `|| echo "{}"` masked auth failures as "empty map" and
#   downstream renderers skipped bundles with misleading messages.
read_tf_output_json() {
  local dir="$1" key="$2" out=""
  if out=$(cd "$dir" && $TOFU output -json "$key" 2>/dev/null); then
    printf '%s\n' "$out"
    return 0
  fi
  if [[ -f "$dir/Makefile" ]]; then
    if out=$(cd "$dir" && printf 'tf-output-json:\n\t@$(TOFU) output -json $(TF_OUTPUT_KEY)\n' \
        | make -s -f Makefile -f - tf-output-json TF_OUTPUT_KEY="$key" TOFU="$TOFU" 2>/dev/null) \
        && [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      return 0
    fi
  fi
  echo "WARN: read_tf_output_json: could not read output '$key' from $dir (state auth? stack not applied?) — returning {}" >&2
  echo "{}"
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
# GCP Secret Manager helpers
# ========================================================================

# get_secret_string_gcp SECRET_ID PROJECT
#   Echo the raw payload of the secret's latest enabled version, or empty
#   string on failure (missing gcloud, IAM denied, secret-without-version,
#   etc). SECRET_ID may be a short name or a full projects/*/secrets/*
#   resource id (the form google_secret_manager_secret.id outputs); the
#   resource id is normalised to the short name because gcloud rejects the
#   full form with a 404.
get_secret_string_gcp() {
  local secret="${1##*/secrets/}" project="$2"
  gcloud secrets versions access latest \
    --secret="$secret" --project="$project" 2>/dev/null || echo ""
}

# get_secret_field_gcp SECRET_ID PROJECT FIELD
#   Echo the value of .FIELD inside the payload JSON, or empty on
#   any failure.
get_secret_field_gcp() {
  local secret="$1" project="$2" field="$3"
  local json
  json=$(get_secret_string_gcp "$secret" "$project")
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
