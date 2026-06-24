#!/usr/bin/env bash
# contract.sh — Sourceable helpers for the ".secure_files env-file contract"
# convention, shared by the two scripts that implement it:
#   - check-env-contract-drift.sh   (VALIDATE: real .env matches its contract)
#   - hydrate-stack-secrets.sh      (POPULATE: write env-supplied values in)
#
# A contract is a template at <secure-dir>/contracts/<stack>.env.example. It
# declares the variable-NAME shape of the real per-stack .env (never values):
#
#   REQUIRED:  ^[A-Za-z_][A-Za-z0-9_]*=            an uncommented   KEY=
#   OPTIONAL:  ^#[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=   a commented   # KEY=
#
# The character class is intentionally broad ([A-Za-z]) so mixed-case names
# such as TF_VAR_foo parse correctly.
#
# The functions print variable names ONE PER LINE in FILE ORDER (no sorting),
# so hydrate can preserve the contract's ordering when it writes. Callers that
# need set semantics (e.g. drift's `comm`) sort/uniq the output themselves.
# Both functions always return 0, even on no match, so they are safe to use
# under `set -e` / `set -o pipefail`.
#
# USAGE
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
#   # shellcheck disable=SC1091
#   source "${SCRIPT_DIR}/lib/contract.sh"
#   names="$(contract_required "<secure-dir>/contracts/<stack>.env.example")"
#
# DESIGN
#   Do NOT enable `set -e` here — this file is sourced; callers own their
#   shell options. These helpers are pure (stdout only, no side effects).

# Uncommented KEY= lines -> REQUIRED variable names, in file order.
contract_required() {
  grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null | sed 's/=.*$//' || true
}

# Commented "# KEY=" lines -> OPTIONAL variable names, in file order.
contract_optional() {
  grep -E '^#[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null \
    | sed -E 's/^#[[:space:]]*//' \
    | sed 's/=.*$//' || true
}
