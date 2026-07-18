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
  printf '2026-07-18 03:30:00\t104.17.1.10\t9.00\t6.80\t6.70\t6.70\t6.75\t200\t200\tpass\tSECRET_PROFILE_HASH\tsidecar_proxy\n'
  printf '2026-07-18 03:31:00\t104.17.1.11\t9.00\t6.40\t6.30\t6.30\t6.35\t200\t200\tlow\tANOTHER_SECRET\tsidecar_proxy\n'
} >"$SOURCE"

"$PYTHON_BIN" "$ROOT/export-candidates.py" \
  --source "$SOURCE" --destination "$DESTINATION" --min-mbps 6.5 >/dev/null
[ "$(wc -l < "$DESTINATION")" -eq 2 ] || { echo "qualified export row count mismatch" >&2; exit 1; }
grep -q $'^cfip-sidecar-candidates-v1\t[0-9]' "$DESTINATION"
grep -q $'\t104.17.1.10\t' "$DESTINATION"
if grep -q 'SECRET\|profile_sha256' "$DESTINATION"; then
  echo "candidate export leaked a forbidden profile field" >&2
  exit 1
fi

{
  printf '%s\n' "$HEADER"
  printf '2026-07-18 03:31:00\t104.17.1.11\t9.00\t6.40\t6.30\t6.30\t6.35\t200\t200\tlow\tSECRET\tsidecar_proxy\n'
} >"$SOURCE"
"$PYTHON_BIN" "$ROOT/export-candidates.py" \
  --source "$SOURCE" --destination "$DESTINATION" --min-mbps 6.5 >/dev/null
[ "$(wc -l < "$DESTINATION")" -eq 1 ] || { echo "empty export must contain only its header" >&2; exit 1; }

printf 'preserve-me\n' >"$DESTINATION"
{
  printf '%s\n' "$HEADER"
  printf '2026-07-18 03:30:00\t203.0.113.9\t9.00\t7.00\t7.00\t7.00\t7.00\t200\t200\tpass\tSECRET\tsidecar_proxy\n'
} >"$SOURCE"
if "$PYTHON_BIN" "$ROOT/export-candidates.py" \
  --source "$SOURCE" --destination "$DESTINATION" --min-mbps 6.5 >/dev/null 2>&1; then
  echo "non-Cloudflare candidate unexpectedly exported" >&2
  exit 1
fi
[ "$(cat "$DESTINATION")" = "preserve-me" ] \
  || { echo "failed export did not preserve the previous file" >&2; exit 1; }

if "$PYTHON_BIN" "$ROOT/export-candidates.py" \
  --source "$SOURCE" --destination "$DESTINATION" --min-mbps 6.49 >/dev/null 2>&1; then
  echo "export threshold below 6.5 MB/s was accepted" >&2
  exit 1
fi

echo "candidate export test passed"
