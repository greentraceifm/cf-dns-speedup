#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1 || ! "$PYTHON_BIN" -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PYTHON_BIN=python
fi
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

SOURCE="$TMP_DIR/observation.tsv"
DESTINATION="$TMP_DIR/export/candidates.latest.tsv"
HEADER=$'observed_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tprofile_sha256\tpath_mode'

{
  printf '%s\n' "$HEADER"
  printf '2026-07-18 03:30:00\t104.17.1.10\t9.00\t6.80\t6.70\t6.70\t6.75\t200\t200\tpass\tSECRET_A\tsidecar_proxy\n'
  printf '2026-07-18 03:31:00\t104.17.1.11\t9.00\t4.20\t4.10\t4.10\t4.15\t200\t200\tlow\tSECRET_B\tsidecar_proxy\n'
  printf '2026-07-18 03:32:00\t104.17.1.12\t9.00\t4.00\t3.90\t3.90\t3.95\t200\t200\tlow\tSECRET_C\tsidecar_proxy\n'
  printf '2026-07-18 03:33:00\t104.17.1.13\t9.00\t3.80\t3.70\t3.70\t3.75\t200\t200\tlow\tSECRET_D\tsidecar_proxy\n'
  printf '2026-07-18 03:34:00\t104.17.1.14\t9.00\t3.40\t3.30\t3.30\t3.35\t200\t200\tlow\tSECRET_E\tsidecar_proxy\n'
} >"$SOURCE"

"$PYTHON_BIN" "$ROOT/export-candidates.py" --source "$SOURCE" --destination "$DESTINATION" \
  --min-mbps 3.5 --excellent-min-mbps 6.5 --limit 3 >/dev/null
[ "$(wc -l < "$DESTINATION")" -eq 4 ] || { echo "top-three export row count mismatch" >&2; exit 1; }
head -n 1 "$DESTINATION" | grep -q $'^schema_version\texported_epoch.*\tcandidate_tier$'
awk -F '\t' 'NR==2 && $1=="cfip-sidecar-candidates-v2" && $4=="104.17.1.10" && $12=="pass" && $14=="excellent" {ok=1} END{exit ok?0:1}' "$DESTINATION"
awk -F '\t' 'NR==3 && $4=="104.17.1.11" && $12=="low" && $14=="observation" {ok=1} END{exit ok?0:1}' "$DESTINATION"
awk -F '\t' 'NR==4 && $4=="104.17.1.12" && $14=="observation" {ok=1} END{exit ok?0:1}' "$DESTINATION"
if grep -q 'SECRET\|profile_sha256' "$DESTINATION"; then
  echo "candidate export leaked a forbidden profile field" >&2
  exit 1
fi

{
  printf '%s\n' "$HEADER"
  printf '2026-07-18 03:34:00\t104.17.1.14\t9.00\t3.40\t3.30\t3.30\t3.35\t200\t200\tlow\tSECRET\tsidecar_proxy\n'
} >"$SOURCE"
"$PYTHON_BIN" "$ROOT/export-candidates.py" --source "$SOURCE" --destination "$DESTINATION" \
  --min-mbps 3.5 --excellent-min-mbps 6.5 --limit 3 >/dev/null
[ "$(wc -l < "$DESTINATION")" -eq 1 ] || { echo "empty export must contain only its header" >&2; exit 1; }

printf 'preserve-me\n' >"$DESTINATION"
{
  printf '%s\n' "$HEADER"
  printf '2026-07-18 03:30:00\t203.0.113.9\t9.00\t4.00\t4.00\t4.00\t4.00\t200\t200\tlow\tSECRET\tsidecar_proxy\n'
} >"$SOURCE"
if "$PYTHON_BIN" "$ROOT/export-candidates.py" --source "$SOURCE" --destination "$DESTINATION" \
  --min-mbps 3.5 --excellent-min-mbps 6.5 --limit 3 >/dev/null 2>&1; then
  echo "non-Cloudflare candidate unexpectedly exported" >&2; exit 1
fi
[ "$(cat "$DESTINATION")" = "preserve-me" ] || { echo "failed export did not preserve previous file" >&2; exit 1; }

for args in '--min-mbps 3.49 --excellent-min-mbps 6.5 --limit 3' '--min-mbps 3.5 --excellent-min-mbps 6.49 --limit 3' '--min-mbps 3.5 --excellent-min-mbps 6.5 --limit 4'; do
  if "$PYTHON_BIN" "$ROOT/export-candidates.py" --source "$SOURCE" --destination "$DESTINATION" $args >/dev/null 2>&1; then
    echo "unsafe export configuration was accepted: $args" >&2; exit 1
  fi
done

echo "candidate export test passed"