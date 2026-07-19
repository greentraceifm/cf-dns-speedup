#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/router-candidate-gate.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/flock" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$TMP_DIR/bin/flock"
export PATH="$TMP_DIR/bin:$PATH"

export APP_DIR="$TMP_DIR/app"
export CONFIG_FILE="$TMP_DIR/missing.env"
export CFIP_CANDIDATE_GATE_LOCK="$TMP_DIR/gate.lock"
HEADER=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode'
NOW="$(date +%s)"
OBSERVED_AT="$(date '+%F %T')"
VALID="$TMP_DIR/valid.tsv"

write_row() {
  local output="$1" epoch="$2" ip="$3" r1="$4" r2="$5" minimum="$6" average="$7"
  {
    printf '%s\n' "$HEADER"
    printf 'cfip-sidecar-candidates-v1\t%s\t%s\t%s\t9.00\t%s\t%s\t%s\t%s\t200\t200\tpass\tsidecar_proxy\n' \
      "$epoch" "$OBSERVED_AT" "$ip" "$r1" "$r2" "$minimum" "$average"
  } > "$output"
}

write_row "$VALID" "$NOW" 104.17.1.10 6.80 6.70 6.70 6.75
bash "$SCRIPT" import "$VALID" > "$TMP_DIR/import.out"
grep -q 'count=1; staging only' "$TMP_DIR/import.out"
bash "$SCRIPT" list | grep -q $'^104.17.1.10\t6.70\t6.75\t'
STAGED="$APP_DIR/candidate-staging/sidecar-candidates.latest.tsv"
BASELINE_SHA="$(sha256sum "$STAGED" | awk '{print $1}')"

expect_reject() {
  local name="$1" source="$2"
  if bash "$SCRIPT" import "$source" > "$TMP_DIR/$name.out" 2>&1; then
    echo "$name unexpectedly passed" >&2
    exit 1
  fi
  [ "$(sha256sum "$STAGED" | awk '{print $1}')" = "$BASELINE_SHA" ] \
    || { echo "$name changed the staged queue after rejection" >&2; exit 1; }
}

write_row "$TMP_DIR/stale.tsv" "$((NOW - 172801))" 104.17.1.11 6.80 6.70 6.70 6.75
expect_reject stale "$TMP_DIR/stale.tsv"
write_row "$TMP_DIR/non-cf.tsv" "$NOW" 203.0.113.9 6.80 6.70 6.70 6.75
expect_reject non_cf "$TMP_DIR/non-cf.tsv"
write_row "$TMP_DIR/low.tsv" "$NOW" 104.17.1.11 6.40 6.30 6.30 6.35
expect_reject low "$TMP_DIR/low.tsv"
write_row "$TMP_DIR/bad-math.tsv" "$NOW" 104.17.1.11 7.00 6.50 7.00 6.75
expect_reject bad_math "$TMP_DIR/bad-math.tsv"

{
  printf '%s\n' "$HEADER"
  tail -n 1 "$VALID"
  tail -n 1 "$VALID"
} > "$TMP_DIR/duplicate.tsv"
expect_reject duplicate "$TMP_DIR/duplicate.tsv"
sed '1s/$/\tprofile_sha256/' "$VALID" > "$TMP_DIR/secret-header.tsv"
expect_reject secret_header "$TMP_DIR/secret-header.tsv"

printf 'CFIP_ROUTER_CANARY_MIN_MBPS=6.4\n' > "$TMP_DIR/unsafe.env"
CONFIG_FILE="$TMP_DIR/unsafe.env" expect_reject unsafe_threshold "$VALID"

printf '%s\n' "$HEADER" > "$TMP_DIR/empty.tsv"
bash "$SCRIPT" import "$TMP_DIR/empty.tsv" > "$TMP_DIR/empty.out"
grep -q 'count=0; staging only' "$TMP_DIR/empty.out"
[ "$(wc -l < "$STAGED")" -eq 1 ] || { echo "empty staging queue must contain only a header" >&2; exit 1; }

cat > "$TMP_DIR/bin/od" <<'EOF'
#!/usr/bin/env sh
echo "od must not be required by the router import path" >&2
exit 127
EOF
chmod +x "$TMP_DIR/bin/od"
PATH="$TMP_DIR/bin:$PATH" bash "$SCRIPT" import "$TMP_DIR/empty.tsv" > "$TMP_DIR/no-od.out"
grep -q 'count=0; staging only' "$TMP_DIR/no-od.out"

HISTORY="$APP_DIR/router-candidate-canary-history.tsv"
QUALIFIED="$APP_DIR/router-candidate-competition-qualified.tsv"
printf 'observed_at\tcandidate_ip\tsource_export_epoch\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tbytes1\tbytes2\tstatus\tpath_mode\n' > "$HISTORY"
printf '%s\t104.17.1.10\t%s\t7.00\t6.80\t6.80\t6.90\t200\t200\t20000000\t20000000\tpass\trouter_isolated_xray\n' \
  "$(date -d '2 days ago' '+%F 03:40:00')" "$((NOW - 172000))" >> "$HISTORY"
printf '%s\t104.17.1.10\t%s\t7.10\t6.90\t6.90\t7.00\t200\t200\t20000000\t20000000\tpass\trouter_isolated_xray\n' \
  "$(date -d '1 day ago' '+%F 03:40:00')" "$((NOW - 86000))" >> "$HISTORY"
bash "$SCRIPT" qualify | grep -q 'competition_qualified_count=0'
printf '%s\t104.17.1.10\t%s\t7.20\t7.00\t7.00\t7.10\t200\t200\t20000000\t20000000\tpass\trouter_isolated_xray\n' \
  "$(date '+%F 03:40:00')" "$NOW" >> "$HISTORY"
bash "$SCRIPT" qualify | grep -q 'competition_qualified_count=1'
awk -F '\t' '$1 == "104.17.1.10" && $2 == 3 && $3 == 3 && $7 == "competition_qualified" {found=1} END {exit found ? 0 : 1}' "$QUALIFIED" \
  || { echo "three distinct days and exports did not qualify the candidate" >&2; exit 1; }

if grep -Eq 'passwall (restart|stop)|/etc/init.d/passwall|uci (set|commit)|api.cloudflare.com' "$SCRIPT"; then
  echo "staging importer contains a forbidden production mutation" >&2
  exit 1
fi

echo "router candidate gate test passed"
