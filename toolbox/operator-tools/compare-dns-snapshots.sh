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

# compare-dns-snapshots.sh
#
# Compares two snapshots produced by capture-dns-snapshot.sh.
# Header comment lines (starting with #) are stripped before diffing so
# capture timestamps do not produce false drift.
#
# Exit 0 = snapshots are 1:1 identical.
# Exit 1 = drift detected.
# Exit 2 = invocation error.
#
# Usage:
#   bash compare-dns-snapshots.sh <baseline.txt> <current.txt>

set -euo pipefail

# Pin collation for consistency with capture-dns-snapshot.sh and
# verify-dns-1to1.sh. Today this script does only byte-wise diff and
# locale-neutral grep, but pinning here keeps the whole toolchain
# byte-stable if future versions add sort/uniq passes.
export LC_ALL=C

BASELINE="${1:?Usage: $0 <baseline.txt> <current.txt>}"
CURRENT="${2:?Usage: $0 <baseline.txt> <current.txt>}"

if [[ ! -f "$BASELINE" ]]; then
  echo "ERROR: baseline file not found: $BASELINE" >&2
  exit 2
fi
if [[ ! -f "$CURRENT" ]]; then
  echo "ERROR: current file not found: $CURRENT" >&2
  exit 2
fi

DIFF_OUTPUT=$(diff <(grep -v '^#' "$BASELINE") <(grep -v '^#' "$CURRENT") || true)

if [[ -z "$DIFF_OUTPUT" ]]; then
  echo "PASS — snapshots are 1:1 identical."
  echo "  baseline: $BASELINE"
  echo "  current:  $CURRENT"
  exit 0
fi

echo "FAIL — DNS drift detected between snapshots:"
echo "  baseline: $BASELINE"
echo "  current:  $CURRENT"
echo ""
echo "Diff (lines starting with '<' are baseline, '>' are current):"
echo "$DIFF_OUTPUT"
exit 1
