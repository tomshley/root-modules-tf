#!/usr/bin/env bash
#
# check-env-contract-drift.sh
#
# Validates that every real per-stack .env file in a secure-files directory
# matches the variable-name shape declared in its contract under
# <secure-dir>/contracts/<stack>.env.example.
#
# Repo-agnostic: the secure-files directory is the first argument (default
# .secure_files, relative to the current working directory), so the same
# checker serves every consumer that adopts the contract convention. The
# contract grammar itself lives in lib/contract.sh.
#
# Drift policy (see the consumer repo's <secure-dir>/contracts/README.md):
#   1. For each <secure-dir>/<env>-<region>-<stack>.env, locate
#      <secure-dir>/contracts/<stack>.env.example (else fail).
#   2. REQUIRED ⊆ real — every REQUIRED var must appear in the real file.
#   3. real ⊆ (REQUIRED ∪ OPTIONAL) — no real var may be absent from contract.
#   4. For each <secure-dir>/contracts/<stack>.env.example with at least one
#      REQUIRED variable, at least one matching <secure-dir>/*-<stack>.env
#      must exist (else fail). Catches the missing-real-file class — pre this
#      check, an absent real .env silently let CI proceed without per-stack
#      credentials, surfacing later as a confusing provider authentication
#      error from inside `tofu plan`. Contracts with no REQUIRED entries are
#      exempt (e.g. a stack that operates entirely on TF-managed secrets with
#      no operator-supplied creds).
#
# Contract parsing rules (implemented in lib/contract.sh):
#   - Lines matching ^[A-Za-z_][A-Za-z0-9_]*=  → REQUIRED variable
#     (the character class spans both cases — TF_VAR_foo style names mix cases.)
#   - Lines matching ^#[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=  → OPTIONAL variable
#   - All other lines (free comments, blanks) ignored
#
# Exit codes:
#   0 — all real .env files match their contracts
#   1 — drift detected (one or more violations printed to stderr)
#   2 — usage error (e.g. <secure-dir>/contracts/ missing)
#
# Usage:
#   bash check-env-contract-drift.sh [SECURE_FILES_DIR]

# NOTE: unlike the other operator-tools scripts this one deliberately does NOT
# `set -euo pipefail`. It walks every real .env and every contract, accumulating
# ALL violations and reporting them together before returning a single summary
# exit code (0/1/2); `set -e` would abort on the first non-zero status —
# including the expected non-zero exit of `grep`/`comm` on empty input — and
# defeat that. `set -u` is likewise avoided so an empty `contract_stacks` array
# stays safe under bash 3.2 (the macOS default).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/contract.sh"

SECURE_FILES_DIR="${1:-.secure_files}"
CONTRACTS_DIR="${SECURE_FILES_DIR}/contracts"

if [ ! -d "${SECURE_FILES_DIR}" ]; then
  echo "ERROR: ${SECURE_FILES_DIR} not found." >&2
  exit 2
fi

if [ ! -d "${CONTRACTS_DIR}" ]; then
  echo "ERROR: ${CONTRACTS_DIR} not found. The contracts/ folder must exist before drift check can run." >&2
  exit 2
fi

# Sorted/uniq'd views of the contract grammar (lib/contract.sh emits file
# order; `comm` below needs sorted input and we want set semantics here).
extract_required() {
  contract_required "$1" | LC_ALL=C sort -u
  return 0
}
extract_optional() {
  contract_optional "$1" | LC_ALL=C sort -u
  return 0
}

violations=0

# Build the set of known stack names from contract filenames, sorted by
# descending length so suffix-matching prefers the longest contract name.
# This handles stacks containing dashes (e.g. foo-bar).
contract_stacks=()
while IFS= read -r stack; do
  [ -z "${stack}" ] && continue
  contract_stacks+=("${stack}")
done < <(
  shopt -s nullglob
  for c in "${CONTRACTS_DIR}"/*.env.example; do
    basename "${c}" .env.example
  done | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-
)

shopt -s nullglob
for envfile in "${SECURE_FILES_DIR}"/*.env; do
  base="$(basename "${envfile}" .env)"

  # Skip the shared .env.
  case "${base}" in
    ""|.env) continue ;;
  esac

  # Resolve <stack> by matching a known contract suffix, so multi-word
  # stack names like foo-bar are parsed correctly.
  stack=""
  for candidate in "${contract_stacks[@]}"; do
    case "${base}" in
      *-"${candidate}")
        stack="${candidate}"
        break
        ;;
    esac
  done

  if [ -z "${stack}" ]; then
    echo "DRIFT: ${envfile} — does not match any known contract suffix (expected <env>-<region>-<stack>.env)." >&2
    violations=$((violations + 1))
    continue
  fi

  contract="${CONTRACTS_DIR}/${stack}.env.example"
  if [ ! -f "${contract}" ]; then
    echo "DRIFT: ${envfile} — no contract at ${contract} for stack '${stack}'." >&2
    violations=$((violations + 1))
    continue
  fi

  required="$(extract_required "${contract}")"
  optional="$(extract_optional "${contract}")"
  actual="$(extract_required "${envfile}")"
  allowed="$(printf '%s\n%s\n' "${required}" "${optional}" | grep -v '^$' | LC_ALL=C sort -u)"

  # Rule 2: REQUIRED ⊆ real (every required var must be in actual).
  missing="$(LC_ALL=C comm -23 <(printf '%s\n' "${required}" | grep -v '^$') <(printf '%s\n' "${actual}" | grep -v '^$'))"
  if [ -n "${missing}" ]; then
    while IFS= read -r var; do
      [ -z "${var}" ] && continue
      echo "DRIFT: ${envfile} missing REQUIRED variable '${var}' (defined in ${contract})." >&2
      violations=$((violations + 1))
    done <<< "${missing}"
  fi

  # Rule 3: real ⊆ (REQUIRED ∪ OPTIONAL) — no rogue variables.
  rogue="$(LC_ALL=C comm -23 <(printf '%s\n' "${actual}" | grep -v '^$') <(printf '%s\n' "${allowed}" | grep -v '^$'))"
  if [ -n "${rogue}" ]; then
    while IFS= read -r var; do
      [ -z "${var}" ] && continue
      echo "DRIFT: ${envfile} has variable '${var}' NOT declared in ${contract} (neither REQUIRED nor OPTIONAL)." >&2
      violations=$((violations + 1))
    done <<< "${rogue}"
  fi
done
shopt -u nullglob

# Rule 4 — every contract with REQUIRED entries must have at least one
# matching real .env file. Keeping this orthogonal to the per-file loop
# above (which only iterates real files) so a contract with NO real
# files surfaces, instead of silently passing because the loop body
# never runs for that stack.
shopt -s nullglob
for contract in "${CONTRACTS_DIR}"/*.env.example; do
  stack="$(basename "${contract}" .env.example)"

  # Skip contracts with no REQUIRED entries — by convention those stacks
  # don't expect operator-supplied creds (future-proofs the rule against a
  # stack whose vars are fully TF-managed).
  required="$(extract_required "${contract}")"
  if [ -z "${required}" ]; then
    continue
  fi

  # Look for at least one real <env>-<region>-<stack>.env. Glob against
  # `*-<stack>.env` (the leading `-` means a bare `<stack>.env` with no
  # env/region prefix is ignored, just as the per-file loop ignores it), then
  # confirm each match resolves to THIS stack (see the inner loop below).
  found=0
  shopt -s nullglob
  for real in "${SECURE_FILES_DIR}"/*-"${stack}".env; do
    real_base="$(basename "${real}" .env)"
    # A file ending in "-${stack}" may actually belong to a LONGER contract
    # whose name also ends in "${stack}" — e.g. a real "...-private-cloud.env"
    # glob-matches the shorter stack "cloud". Re-resolve via the same
    # longest-suffix rule the per-file loop uses and count the file only when it
    # maps to THIS stack, so a longer sibling cannot mask this stack's missing
    # real file (this also handles the leading-dash "-${stack}.env" form the
    # same way the per-file loop does).
    resolved=""
    for candidate in "${contract_stacks[@]}"; do
      case "${real_base}" in
        *-"${candidate}") resolved="${candidate}"; break ;;
      esac
    done
    [ "${resolved}" = "${stack}" ] || continue
    found=1
    break
  done
  shopt -u nullglob

  if [ "${found}" -eq 0 ]; then
    echo "DRIFT: contract ${contract} declares REQUIRED variables but no matching real ${SECURE_FILES_DIR}/<env>-<region>-${stack}.env file exists." >&2
    echo "       Without it, this stack has no operator-supplied credentials and downstream tooling (e.g. tofu plan/apply) will fail with a provider authentication error." >&2
    echo "       Operator: provide <env>-<region>-${stack}.env via your secret store / CI secure files, or create it locally for dev." >&2
    violations=$((violations + 1))
  fi
done
shopt -u nullglob

if [ "${violations}" -gt 0 ]; then
  echo "" >&2
  echo "Contract drift check FAILED with ${violations} violation(s)." >&2
  echo "See the consumer repo's <secure-dir>/contracts/README.md for the contract convention." >&2
  exit 1
fi

echo "Contract drift check passed: all per-stack .env files match their contracts."
exit 0
