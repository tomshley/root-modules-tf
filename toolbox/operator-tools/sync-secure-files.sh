#!/usr/bin/env bash
# sync-secure-files.sh — Upload local .secure_files/ to GitLab Secure Files via API.
#
# Syncs every non-example file in the secure directory to the GitLab project's
# CI/CD Secure Files store.  For each local file the script deletes the existing
# remote copy (if any) and uploads the current local version.
#
# Usage:
#   ./sync-secure-files.sh --project-id <id> [--token <pat>] [--secure-dir <path>]
#
# Arguments:
#   --project-id  Required. Numeric GitLab project ID.
#   --token       GitLab Personal Access Token with api scope.
#                 Falls back to GITLAB_TOKEN env var.
#   --secure-dir  Path to the local .secure_files/ directory (default: .secure_files).
#   --gitlab-url  GitLab API base URL (default: https://gitlab.com).
#
# Environment:
#   GITLAB_TOKEN  Used when --token is not provided.
#
# Requires: curl, jq.

set -euo pipefail

TMP_DIR=""

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

# --- Parse arguments ---
PROJECT_ID=""
TOKEN="${GITLAB_TOKEN:-}"
SECURE_DIR=".secure_files"
GITLAB_URL="https://gitlab.com"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-id) PROJECT_ID="$2"; shift 2 ;;
    --token)      TOKEN="$2";      shift 2 ;;
    --secure-dir) SECURE_DIR="$2"; shift 2 ;;
    --gitlab-url) GITLAB_URL="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --project-id <id> [--token <pat>] [--secure-dir <path>]" >&2
      exit 1
      ;;
  esac
done

# --- Validate arguments ---
if [[ -z "$PROJECT_ID" ]]; then
  echo "Error: --project-id is required" >&2; exit 1
fi
if [[ -z "$TOKEN" ]]; then
  echo "Error: --token or GITLAB_TOKEN env var is required" >&2; exit 1
fi
if [[ ! -d "$SECURE_DIR" ]]; then
  echo "Error: secure directory not found: $SECURE_DIR" >&2; exit 1
fi

for cmd in curl jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is required but not found in PATH" >&2; exit 1
  fi
done

API="${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/secure_files"
TMP_DIR=$(mktemp -d)

echo "Syncing secure files to GitLab project $PROJECT_ID"
echo "  secure-dir: $SECURE_DIR"
echo ""

download_secure_file() {
  local remote_id="$1" output_path="$2" attempt
  for attempt in 1 2 3; do
    if curl -sS --fail --header "PRIVATE-TOKEN: $TOKEN" \
      "${API}/${remote_id}/download" -o "$output_path"; then
      return 0
    fi
    rm -f "$output_path"
    sleep "$attempt"
  done
  return 1
}

delete_secure_file() {
  local remote_id="$1" http_code="" attempt
  for attempt in 1 2 3; do
    http_code=$(curl -sS -o /dev/null -w "%{http_code}" --request DELETE \
      --header "PRIVATE-TOKEN: $TOKEN" "${API}/${remote_id}" || true)
    if [[ "$http_code" == "204" ]]; then
      return 0
    fi
    sleep "$attempt"
  done
  return 1
}

upload_secure_file() {
  local name="$1" source_file="$2" response="" new_id="" attempt
  for attempt in 1 2 3; do
    response=$(curl -sS --fail --request POST --header "PRIVATE-TOKEN: $TOKEN" \
      --form "name=$name" --form "file=@$source_file" "$API" || true)
    new_id=$(echo "$response" | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -n "$new_id" ]]; then
      echo "$new_id"
      return 0
    fi
    sleep "$attempt"
  done
  return 1
}

# --- Fetch current remote inventory ---
REMOTE_JSON=$(curl -sf --header "PRIVATE-TOKEN: $TOKEN" "${API}?per_page=100") || {
  echo "Error: failed to list remote secure files (check project ID and token)" >&2; exit 1
}

# --- Collect local files (non-example, including dotfiles) ---
LOCAL_FILES=()
for f in "$SECURE_DIR"/* "$SECURE_DIR"/.*; do
  [[ -f "$f" ]] || continue
  fname=$(basename "$f")
  [[ "$fname" == "." || "$fname" == ".." ]] && continue
  [[ "$fname" == *.example ]] && continue
  [[ "$fname" == ".gitkeep" ]] && continue
  [[ ! -s "$f" ]] && continue  # skip zero-byte files (GitLab Secure Files API returns 500)
  LOCAL_FILES+=("$f")
done

if [[ ${#LOCAL_FILES[@]} -eq 0 ]]; then
  echo "No files to sync in $SECURE_DIR"
  exit 0
fi

# --- Sync each file ---
OK=0

for LOCAL_FILE in "${LOCAL_FILES[@]}"; do
  FNAME=$(basename "$LOCAL_FILE")

  # Check if remote has this file
  REMOTE_ID=$(echo "$REMOTE_JSON" | jq -r --arg name "$FNAME" '.[] | select(.name == $name) | .id // empty')
  REMOTE_BACKUP=""

  if [[ -n "$REMOTE_ID" ]]; then
    REMOTE_BACKUP="$TMP_DIR/${REMOTE_ID}-$(basename "$FNAME")"
    if ! download_secure_file "$REMOTE_ID" "$REMOTE_BACKUP"; then
      echo "  FAIL GET $FNAME (id=$REMOTE_ID)" >&2
      exit 1
    fi
    if ! delete_secure_file "$REMOTE_ID"; then
      echo "  FAIL DEL $FNAME (id=$REMOTE_ID)" >&2
      exit 1
    fi
  fi

  NEW_ID=$(upload_secure_file "$FNAME" "$LOCAL_FILE" || true)

  if [[ -n "$NEW_ID" ]]; then
    if [[ -n "$REMOTE_ID" ]]; then
      echo "  UPD $FNAME → id=$NEW_ID"
    else
      echo "  ADD $FNAME → id=$NEW_ID"
    fi
    OK=$((OK + 1))
  else
    if [[ -n "$REMOTE_BACKUP" ]]; then
      RESTORED_ID=$(upload_secure_file "$FNAME" "$REMOTE_BACKUP" || true)
      if [[ -n "$RESTORED_ID" ]]; then
        echo "  FAIL PUT $FNAME (restored previous remote copy as id=$RESTORED_ID)" >&2
      else
        echo "  FAIL PUT $FNAME (rollback failed; remote file was deleted)" >&2
      fi
    else
      echo "  FAIL PUT $FNAME" >&2
    fi
    exit 1
  fi
done

echo ""
echo "Done: $OK synced, 0 failed"
