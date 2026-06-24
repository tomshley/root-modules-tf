#!/usr/bin/env bash
#
# hydrate-stack-secrets.sh
#
# Write operator-supplied secret VALUES into a stack's real per-environment
# .env file, driven entirely by that stack's contract
# (<secure-dir>/contracts/<stack>.env.example).
#
# The contract is the single source of truth for which secret keys a stack
# needs and which .env file they belong in — the same contract enforced by
# check-env-contract-drift.sh (the grammar is shared in lib/contract.sh). This
# script is the WRITE side of that contract: callers supply only VALUES (via
# the process environment) and the contract decides which keys get written
# where. No specific secret store or caller is encoded here, so CI, an operator
# shell, or any provisioning tool can drive it identically WITHOUT
# re-implementing the key-to-file mapping.
#
# Contract-driven, so it never hardcodes key names:
#   - REQUIRED keys  (^KEY=        in the contract)
#   - OPTIONAL keys  (^# KEY=      in the contract)
#   For each contract key, if a same-named environment variable is set and
#   non-empty, its value is upserted into the real .env. Missing OPTIONAL keys
#   are skipped silently; missing REQUIRED keys warn (and fail under --strict).
#   Values never appear in output — only key names.
#
# It only ever writes the keys the contract declares, so it cannot introduce
# drift: the output of a hydrate run always passes check-env-contract-drift.sh
# for the keys it touched.
#
# Usage:
#   hydrate-stack-secrets.sh \
#     --stack <stack> --env <env> --region <region> [--secure-dir <path>]
#
#   # values come from the environment, matching the contract key names:
#   EXAMPLE_API_KEY=… EXAMPLE_API_SECRET=… TF_VAR_example_token=… \
#     hydrate-stack-secrets.sh --stack <stack> --secure-dir /path/.secure_files
#
# Flags:
#   --stack <name>      REQUIRED. Contract basename (matches contracts/<name>.env.example).
#   --env <env>         Environment prefix. Default: staging.
#   --region <region>   Region segment. Default: us-east-1. Pass empty ("") for
#                       global (account-wide) stacks -> <env>-<stack>.env.
#   --infra-dir <path>  Consumer repo root. Default: current directory.
#   --secure-dir <path> Secure-files dir. Default: <infra-dir>/.secure_files.
#   --dry-run           Print what would be written; touch nothing.
#   --apply             Write (default).
#   --strict            Exit non-zero if any REQUIRED contract key is absent
#                       from the environment.
#   -h, --help          This help.
#
# Exit codes:
#   0  success (or dry-run)
#   1  --strict and one or more REQUIRED keys were missing from the environment
#   2  usage error / contract not found
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/contract.sh"

STACK=""
ENVIRONMENT="staging"
REGION="us-east-1"
INFRA_DIR="."
SECURE_DIR=""
APPLY=true
STRICT=false

usage() { sed -n '2,/^set -euo pipefail$/{/^set -euo pipefail$/d;s/^# \{0,1\}//;p;}' "$0"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --stack)      STACK="${2:-}"; shift 2 ;;
    --env)        ENVIRONMENT="${2:-}"; shift 2 ;;
    --region)     REGION="${2:-}"; shift 2 ;;
    --infra-dir)  INFRA_DIR="${2:-}"; shift 2 ;;
    --secure-dir) SECURE_DIR="${2:-}"; shift 2 ;;
    --dry-run)    APPLY=false; shift ;;
    --apply)      APPLY=true; shift ;;
    --strict)     STRICT=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; echo "Try --help." >&2; exit 2 ;;
  esac
done

if [ -z "$STACK" ]; then
  echo "ERROR: --stack is required." >&2
  exit 2
fi

[ -z "$SECURE_DIR" ] && SECURE_DIR="${INFRA_DIR%/}/.secure_files"
CONTRACT="${SECURE_DIR}/contracts/${STACK}.env.example"

if [ ! -f "$CONTRACT" ]; then
  echo "ERROR: contract not found: ${CONTRACT}" >&2
  echo "       Stack '${STACK}' has no contracts/${STACK}.env.example under ${SECURE_DIR}." >&2
  exit 2
fi

# Real per-environment file name. Global (region-less) stacks use <env>-<stack>.env.
if [ -n "$REGION" ]; then
  REAL_NAME="${ENVIRONMENT}-${REGION}-${STACK}.env"
else
  REAL_NAME="${ENVIRONMENT}-${STACK}.env"
fi
REAL_FILE="${SECURE_DIR}/${REAL_NAME}"

# ── symlink-safe write ──────────────────────────────────────────────────────
# Some workspaces symlink .secure_files/*.env into a consolidated secret store;
# resolve to the real target so we write THROUGH the link instead of replacing
# it with a regular file. No-op for normal files / CI.
resolve_link() {
  local f="$1"
  while [ -L "$f" ]; do
    local t; t="$(readlink "$f")"
    case "$t" in
      /*) f="$t" ;;
      *)  f="$(dirname "$f")/$t" ;;
    esac
  done
  printf '%s\n' "$f"
}

# Upsert KEY=value, preserving line position; portable across BSD/GNU (no sed -i).
upsert_var() {
  local file="$1" key="$2" val="$3" tmp replaced=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/hydrate.XXXXXX")"
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "${key}="*) printf '%s=%s\n' "$key" "$val"; replaced=1 ;;
        *)          printf '%s\n' "$line" ;;
      esac
    done < "$file" > "$tmp"
  fi
  [ "$replaced" -eq 0 ] && printf '%s=%s\n' "$key" "$val" >> "$tmp"
  cat "$tmp" > "$file"          # write-through: follows a symlink, keeps the link
  rm -f "$tmp"
  chmod 600 "$file" 2>/dev/null || true
}

required="$(contract_required "$CONTRACT")"
optional="$(contract_optional "$CONTRACT")"

echo "Hydrating ${REAL_NAME} from contract ${STACK}.env.example"
$APPLY || echo "  (dry-run — no files will be written)"

write_target="$REAL_FILE"
if $APPLY; then
  # Resolve symlink target only when the real file already exists.
  [ -e "$REAL_FILE" ] && write_target="$(resolve_link "$REAL_FILE")"
fi

written=0
missing_required=0
skipped_optional=0

hydrate_keys() {
  local kind="$1" names="$2" name val
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    val="${!name:-}"
    if [ -n "$val" ]; then
      if $APPLY; then
        # Create the file lazily on first real write, chmod 600 up front.
        if [ ! -e "$write_target" ]; then
          : > "$write_target"
          chmod 600 "$write_target" 2>/dev/null || true
        fi
        upsert_var "$write_target" "$name" "$val"
        echo "  ✓ ${name}=<redacted>"
      else
        echo "  [dry-run] would set ${name}=<redacted>"
      fi
      written=$((written + 1))
    else
      if [ "$kind" = required ]; then
        echo "  WARN: REQUIRED '${name}' not set in environment — skipped." >&2
        missing_required=$((missing_required + 1))
      else
        skipped_optional=$((skipped_optional + 1))
      fi
    fi
  done <<< "$names"
}

hydrate_keys required "$required"
hydrate_keys optional "$optional"

echo "  Summary: ${written} written, ${missing_required} required-missing, ${skipped_optional} optional-absent."

if [ "$missing_required" -gt 0 ] && $STRICT; then
  echo "ERROR: --strict and ${missing_required} REQUIRED key(s) missing from environment." >&2
  exit 1
fi

exit 0
