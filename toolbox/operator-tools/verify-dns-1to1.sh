#!/usr/bin/env bash
# verify-dns-1to1.sh
#
# Semantic 1:1 verification of authoritative DNS state against BIND-format
# zone exports. Verifies, per (fqdn, type) RRset:
#
#   - All-non-proxied RRset:
#       The live RRset (the full set returned by dig +short, byte-normalized
#       per record type) must EQUAL the BIND-declared RRset, set-equal. Both
#       missing values (in BIND, absent from live) and extra values (in live,
#       absent from BIND) count as DRIFT and are reported individually.
#
#   - Any-proxied RRset (>=1 record carries `; cf-proxied:true` in BIND):
#       The live answer must be non-empty. The live answer differs from the
#       origin values by design (Cloudflare returns its anycast addresses, not
#       the origin), so byte-equality is not enforceable. PASS = "alive".
#
# SOA and apex NS are skipped — both are managed at the registrar/parent-zone
# level and BIND export shape varies across providers; capture-dns-snapshot.sh
# captures them for the snapshot pair so drift on those still surfaces in the
# byte-stable diff path.
#
# Bound: the BIND export directory IS the authoritative source-of-truth. The
# script catches every divergence within RRsets that BIND describes. It does
# NOT enumerate "live records that don't exist in BIND at all" because public
# DNS does not support enumerate-zone-records over `dig` (only AXFR or vendor
# API does, and both are out-of-scope for this `dig`+`awk`+`diff` toolchain).
# Therefore: the export must be a complete dump of the zone — for Cloudflare,
# the dashboard's "Export DNS records" button produces that.
#
# Intended use: pre-apply and post-apply cutover gate. Pair with
# capture-dns-snapshot.sh and compare-dns-snapshots.sh for the rollback
# evidence chain.
#
# Usage:
#   bash verify-dns-1to1.sh <bind-export-dir>
#
# Environment:
#   NAMESERVER  - authoritative nameserver to query (default: 1.1.1.1)

set -euo pipefail

# Pin collation so awk/sort/comm output is byte-stable across operator
# laptops, CI runners, and incident-response shells.
export LC_ALL=C

BIND_EXPORT_DIR="${1:?Usage: $0 <bind-export-dir>}"
NAMESERVER="${NAMESERVER:-1.1.1.1}"

EXACT_MATCH_COUNT=0
PROXIED_ALIVE_COUNT=0
DRIFT_COUNT=0

echo "=== DNS 1:1 Verification ==="
echo "BIND exports: $BIND_EXPORT_DIR"
echo "Authoritative NS: $NAMESERVER"
echo ""

# Phase 1: parse every BIND export into a single tab-separated tuple file.
# Each line: <zone>\t<fqdn>\t<type>\t<proxied>\t<value>
# zone   - the basename of the source BIND file (used for output grouping
#          and immune to the .co.uk / multi-label-apex ambiguity that
#          deriving the zone from the FQDN's suffix would have).
# proxied is one of: true | false | none (no cf-proxied marker)
# value is normalized for the type (trailing-dot stripped on FQDN-bearing
# types; internal whitespace collapsed to a single space).
RECORDS_FILE=$(mktemp)
trap 'rm -f "$RECORDS_FILE"' EXIT

zone_file_count=0
for zone_file in "$BIND_EXPORT_DIR"/*.txt; do
  [[ -f "$zone_file" ]] || continue
  zone_file_count=$((zone_file_count + 1))
  zone=$(basename "$zone_file" .txt)

  while IFS= read -r line; do
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*\; ]] && continue
    [[ "$line" =~ ^[[:space:]]*\$ ]] && continue

    # Detect proxied state from the raw line BEFORE comment-stripping. The
    # marker may appear anywhere in the inline BIND comment portion, in the
    # form `cf_tags=cf-proxied:<bool>` (Cloudflare's actual export format).
    # Operator-authored comment text may precede it, e.g.
    #   ; operator-authored-label cf_tags=cf-proxied:false
    proxied=none
    if echo "$line" | grep -qE 'cf_tags=cf-proxied:true\b'; then
      proxied=true
    elif echo "$line" | grep -qE 'cf_tags=cf-proxied:false\b'; then
      proxied=false
    fi

    # Strip BIND inline comment from the line before field parsing. A BIND
    # comment is introduced by an UNQUOTED `;`; semicolons inside a TXT
    # record's double-quoted value (DMARC policies use `;` as a tag
    # separator: `v=DMARC1; p=quarantine; rua=…`) are part of the value
    # and must not be stripped. Walk character-by-character, tracking
    # quote state, and cut at the first `;` outside quotes. Without this,
    # every TXT record whose content contains a `;` is silently truncated
    # at the first internal semicolon and surfaces as DRIFT against the
    # un-truncated live answer returned by `dig +short TXT`.
    line_no_comment=$(echo "$line" | awk '{
      in_quote = 0
      out = ""
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\"") in_quote = !in_quote
        if (c == ";" && !in_quote) break
        out = out c
      }
      sub(/[[:space:]]+$/, "", out)
      print out
    }')

    name=$(echo "$line_no_comment" | awk '{print $1}')
    type=$(echo "$line_no_comment" | awk '{print $4}')
    value=$(echo "$line_no_comment" | awk '{$1=$2=$3=$4=""; print $0}' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    # Defensive: skip degenerate lines. An empty type indicates either a
    # multi-line SOA continuation (some BIND exporters emit SOA across
    # multiple lines with the bracketed-tuple form) or a truncated record;
    # either way it is not a verifiable RR.
    [[ -z "$type" ]] && continue
    [[ "$type" == "SOA" || "$type" == "NS" ]] && continue
    [[ -z "$value" ]] && continue

    fqdn="$name"
    [[ "$name" == "@" ]] && fqdn="$zone"
    [[ "$name" != *. ]] && [[ "$name" != "@" ]] && fqdn="$name.$zone"
    fqdn="${fqdn%.}"

    # Strip trailing dot on FQDN-bearing types so BIND-side and dig-side
    # normalize identically.
    case "$type" in
      CNAME|MX|SRV|PTR)
        value=$(echo "$value" | sed 's/\.$//')
        ;;
    esac

    # Collapse internal whitespace defensively (BIND tabs).
    value=$(echo "$value" | tr -s '[:space:]' ' ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

    printf '%s\t%s\t%s\t%s\t%s\n' "$zone" "$fqdn" "$type" "$proxied" "$value" >> "$RECORDS_FILE"
  done < "$zone_file"
done

if [[ "$zone_file_count" -eq 0 ]]; then
  echo "ERROR: no .txt zone files found in $BIND_EXPORT_DIR" >&2
  exit 2
fi

if [[ ! -s "$RECORDS_FILE" ]]; then
  echo "ERROR: zone files contained zero verifiable records (only SOA/NS/directives?)" >&2
  exit 2
fi

# Sort + dedup so groups are contiguous and identical-line duplicates are
# merged. Sort key is the natural tab-separated order: zone, then fqdn,
# then type, then proxied, then value. Zone-first ordering keeps all
# records of one zone contiguous in the output regardless of fqdn label
# count, so the per-zone heading does not interleave across zones.
sort -u "$RECORDS_FILE" -o "$RECORDS_FILE"

# Phase 2: walk the sorted tuple file grouped by (fqdn, type) and verify
# each group as an RRset.

# Per-group accumulators.
group_key=""
group_values=""    # newline-separated normalized values
group_proxied=""   # "all-none-or-false" | "any-true"
group_count=0

# compare_group emits one ✓/✗ line for the (fqdn, type) group it is given,
# updating the global counters. For all-non-proxied groups it does an exact
# RRset comm-diff; for any-proxied groups it does a non-empty live check.
compare_group() {
  local fqdn="$1"
  local type="$2"
  local proxied_state="$3"
  local expected_block="$4"
  local count="$5"

  if [[ "$proxied_state" == "any-true" ]]; then
    # Cloudflare's edge proxy flattens proxied CNAMEs and returns its own
    # anycast A (and optional AAAA) records on the wire. Querying the
    # BIND-declared type for a proxied CNAME returns an empty CNAME
    # answer section even though the FQDN resolves. Ask for A; fall back
    # to AAAA. Either non-empty answer proves the edge is alive.
    if dig +short "@$NAMESERVER" "$fqdn" A 2>/dev/null | grep -q . \
       || dig +short "@$NAMESERVER" "$fqdn" AAAA 2>/dev/null | grep -q .; then
      echo "  ✓ PROXIED $type $fqdn (alive, ${count} BIND record(s))"
      PROXIED_ALIVE_COUNT=$((PROXIED_ALIVE_COUNT + 1))
    else
      echo "  ✗ PROXIED $type $fqdn (NOT RESOLVING, expected ${count} record(s))"
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
    fi
    return
  fi

  # All-non-proxied path: exact RRset match.
  local live_block
  live_block=$(dig +short "@$NAMESERVER" "$fqdn" "$type" 2>/dev/null || true)

  case "$type" in
    CNAME|MX|SRV|PTR)
      live_block=$(echo "$live_block" | sed 's/\.$//')
      ;;
  esac

  # Sort both sides byte-stably (LC_ALL=C is exported above).
  local expected_sorted live_sorted
  expected_sorted=$(printf '%s\n' "$expected_block" | grep -v '^$' | sort -u)
  live_sorted=$(printf '%s\n' "$live_block" | grep -v '^$' | sort -u)

  if [[ "$expected_sorted" == "$live_sorted" ]]; then
    echo "  ✓ $type $fqdn (${count} value(s))"
    EXACT_MATCH_COUNT=$((EXACT_MATCH_COUNT + 1))
    return
  fi

  echo "  ✗ $type $fqdn DRIFT"
  local missing extra
  missing=$(comm -23 <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$live_sorted") | grep -v '^$' || true)
  extra=$(comm -13 <(printf '%s\n' "$expected_sorted") <(printf '%s\n' "$live_sorted") | grep -v '^$' || true)
  if [[ -n "$missing" ]]; then
    echo "    Missing (declared in BIND, absent from live):"
    echo "$missing" | sed 's/^/      - /'
  fi
  if [[ -n "$extra" ]]; then
    echo "    Extra (present in live, absent from BIND):"
    echo "$extra" | sed 's/^/      + /'
  fi
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

current_zone=""
while IFS=$'\t' read -r zone fqdn type proxied value; do
  # Zone-change: flush any pending group under the OLD zone heading first,
  # THEN switch the heading. Doing the switch before the flush would print
  # the prior group's comparison line under the new zone, which is wrong.
  if [[ "$zone" != "$current_zone" ]]; then
    if [[ -n "$group_key" ]]; then
      prev_fqdn="${group_key%|*}"
      prev_type="${group_key##*|}"
      compare_group "$prev_fqdn" "$prev_type" "$group_proxied" "$group_values" "$group_count"
      group_key=""
    fi
    if [[ -n "$current_zone" ]]; then
      echo ""
    fi
    echo "--- Zone: $zone ---"
    current_zone="$zone"
  fi

  key="$fqdn|$type"
  if [[ "$key" != "$group_key" ]]; then
    if [[ -n "$group_key" ]]; then
      prev_fqdn="${group_key%|*}"
      prev_type="${group_key##*|}"
      compare_group "$prev_fqdn" "$prev_type" "$group_proxied" "$group_values" "$group_count"
    fi
    group_key="$key"
    group_values="$value"
    group_count=1
    if [[ "$proxied" == "true" ]]; then
      group_proxied="any-true"
    else
      group_proxied="all-none-or-false"
    fi
  else
    group_values=$(printf '%s\n%s' "$group_values" "$value")
    group_count=$((group_count + 1))
    if [[ "$proxied" == "true" ]]; then
      group_proxied="any-true"
    fi
  fi
done < "$RECORDS_FILE"

# Emit final group.
if [[ -n "$group_key" ]]; then
  prev_fqdn="${group_key%|*}"
  prev_type="${group_key##*|}"
  compare_group "$prev_fqdn" "$prev_type" "$group_proxied" "$group_values" "$group_count"
fi

echo ""
echo "=== Summary ==="
echo "Exact RRset matches:  $EXACT_MATCH_COUNT"
echo "Proxied RRsets alive: $PROXIED_ALIVE_COUNT"
echo "Drift detected:       $DRIFT_COUNT"

if [[ "$DRIFT_COUNT" -gt 0 ]]; then
  echo ""
  echo "FAIL — drift detected. Do not proceed with apply."
  exit 1
else
  echo ""
  echo "PASS — 0 drift. Safe to apply."
  exit 0
fi
