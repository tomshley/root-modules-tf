#!/usr/bin/env bash
# capture-dns-snapshot.sh
#
# Captures a deterministic snapshot of every authoritative DNS record across
# one or more zones via dig. Output is sorted text, suitable for byte-for-byte
# diff against a later snapshot.
#
# Intended use: rollback baseline for DNS migrations into Terraform-managed
# state. Capture before plan, after plan, and after apply. Any drift between
# snapshots from the same DNS state is a hard stop.
#
# Input is a directory of BIND-format zone export files (one per zone, named
# <zone>.txt). The script reads each file to enumerate the (fqdn, type) pairs
# to probe, then queries an authoritative nameserver for each pair.
#
# Usage:
#   bash capture-dns-snapshot.sh <bind-export-dir> <output-file>
#
# Environment:
#   NAMESERVER  - authoritative nameserver to query (default: 1.1.1.1)
#                 Override with the zone's authoritative NS for strongest
#                 guarantee, e.g. NAMESERVER=ns1.example.net.

set -euo pipefail

# Pin collation so sort output is byte-stable across operator laptops (typically
# en_US.UTF-8), CI runners (typically C / C.UTF-8), and incident-response shells.
# Without this, two snapshots from the same DNS state captured on different
# locales diff to non-zero and defeat the rollback-evidence chain.
export LC_ALL=C

BIND_EXPORT_DIR="${1:?Usage: $0 <bind-export-dir> <output-file>}"
OUTPUT_FILE="${2:?Usage: $0 <bind-export-dir> <output-file>}"
NAMESERVER="${NAMESERVER:-1.1.1.1}"

if [[ ! -d "$BIND_EXPORT_DIR" ]]; then
  echo "ERROR: BIND export dir not found: $BIND_EXPORT_DIR" >&2
  exit 1
fi

TMP_FILE=$(mktemp)
RECORDS_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE" "$RECORDS_FILE"' EXIT

{
  echo "# DNS snapshot captured $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Authoritative nameserver: $NAMESERVER"
  echo "# BIND export source: $BIND_EXPORT_DIR"
  echo ""
} > "$TMP_FILE"

for zone_file in "$BIND_EXPORT_DIR"/*.txt; do
  [[ -f "$zone_file" ]] || continue
  zone=$(basename "$zone_file" .txt)

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*\; ]] && continue
    [[ "$line" =~ ^[[:space:]]*\$ ]] && continue

    name=$(echo "$line" | awk '{print $1}')
    type=$(echo "$line" | awk '{print $4}')

    # Defensive: skip degenerate lines. An empty type indicates either a
    # multi-line SOA continuation (some BIND exporters emit SOA across
    # multiple lines with the bracketed-tuple form) or a truncated record;
    # either way it is not a probeable RR.
    [[ -z "$type" ]] && continue
    [[ "$type" == "SOA" ]] && continue

    fqdn="$name"
    [[ "$name" == "@" ]] && fqdn="$zone"
    if [[ "$name" != *. ]] && [[ "$name" != "@" ]]; then
      fqdn="$name.$zone"
    fi
    fqdn="${fqdn%.}"

    echo "$fqdn|$type"
  done < <(grep -v "^;" "$zone_file" | grep -v "^[[:space:]]*$") >> "$RECORDS_FILE"

  # Also probe apex AAAA + NS — some providers synthesize AAAA on proxied A
  # records, and vestigial NS records from prior providers can persist.
  # Capturing them ensures any silent change appears in the diff.
  echo "$zone|AAAA" >> "$RECORDS_FILE"
  echo "$zone|NS" >> "$RECORDS_FILE"
done

sort -u "$RECORDS_FILE" -o "$RECORDS_FILE"

echo "Capturing $(wc -l < "$RECORDS_FILE" | tr -d ' ') unique fqdn|type pairs..." >&2

while IFS='|' read -r fqdn type; do
  [[ -z "$fqdn" || -z "$type" ]] && continue
  values=$(dig +short "@$NAMESERVER" "$fqdn" "$type" 2>/dev/null | sort | tr '\n' ';' | sed 's/;$//')
  printf '%s\t%s\t%s\n' "$fqdn" "$type" "$values"
done < "$RECORDS_FILE" | sort >> "$TMP_FILE"

mkdir -p "$(dirname "$OUTPUT_FILE")"
mv "$TMP_FILE" "$OUTPUT_FILE"

echo "Snapshot written: $OUTPUT_FILE" >&2
echo "Lines: $(wc -l < "$OUTPUT_FILE" | tr -d ' ')" >&2
