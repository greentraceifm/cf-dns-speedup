#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/router-candidate-gate.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"
printf '#!/usr/bin/env sh\nexit 0\n' >"$TMP_DIR/bin/flock"
chmod +x "$TMP_DIR/bin/flock"
export PATH="$TMP_DIR/bin:$PATH"
export APP_DIR="$TMP_DIR/app"
export CONFIG_FILE="$TMP_DIR/missing.env"
export CFIP_CANDIDATE_GATE_LOCK="$TMP_DIR/gate.lock"
V1_HEADER=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode'
V2_HEADER=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode\tcandidate_tier'
NOW="$(date +%s)"
OBSERVED_AT="$(date '+%F %T')"

write_v1() {
  printf '%s\ncfip-sidecar-candidates-v1\t%s\t%s\t%s\t9.00\t%s\t%s\t%s\t%s\t200\t200\tpass\tsidecar_proxy\n' \
    "$V1_HEADER" "$2" "$OBSERVED_AT" "$3" "$4" "$5" "$6" "$7" >"$1"
}
write_v2() {
  printf '%s\ncfip-sidecar-candidates-v2\t%s\t%s\t%s\t9.00\t%s\t%s\t%s\t%s\t200\t200\t%s\tsidecar_proxy\t%s\n' \
    "$V2_HEADER" "$2" "$OBSERVED_AT" "$3" "$4" "$5" "$6" "$7" "$8" "$9" >"$1"
}

V1="$TMP_DIR/v1.tsv"; V2="$TMP_DIR/v2.tsv"
write_v1 "$V1" "$NOW" 104.17.1.10 6.80 6.70 6.70 6.75
bash "$SCRIPT" import "$V1" | grep -q 'count=1; staging only'
write_v2 "$V2" "$NOW" 104.17.1.11 4.20 4.00 4.00 4.10 low observation
bash "$SCRIPT" import "$V2" | grep -q 'count=1; staging only'
bash "$SCRIPT" list | grep -q $'^104.17.1.11\t4.00\t4.10\t'
STAGED="$APP_DIR/candidate-staging/sidecar-candidates.latest.tsv"
BASELINE_SHA="$(sha256sum "$STAGED" | awk '{print $1}')"

expect_reject() {
  if bash "$SCRIPT" import "$2" >"$TMP_DIR/$1.out" 2>&1; then echo "$1 unexpectedly passed" >&2; exit 1; fi
  [ "$(sha256sum "$STAGED" | awk '{print $1}')" = "$BASELINE_SHA" ] || { echo "$1 changed staging" >&2; exit 1; }
}
write_v2 "$TMP_DIR/stale.tsv" "$((NOW-172801))" 104.17.1.12 4.20 4.00 4.00 4.10 low observation
expect_reject stale "$TMP_DIR/stale.tsv"
write_v2 "$TMP_DIR/non-cf.tsv" "$NOW" 203.0.113.9 4.20 4.00 4.00 4.10 low observation
expect_reject non_cf "$TMP_DIR/non-cf.tsv"
write_v2 "$TMP_DIR/below-floor.tsv" "$NOW" 104.17.1.12 3.50 3.40 3.40 3.45 low observation
expect_reject below_floor "$TMP_DIR/below-floor.tsv"
write_v2 "$TMP_DIR/bad-tier.tsv" "$NOW" 104.17.1.12 4.20 4.00 4.00 4.10 pass excellent
expect_reject bad_tier "$TMP_DIR/bad-tier.tsv"
write_v2 "$TMP_DIR/bad-math.tsv" "$NOW" 104.17.1.12 4.20 4.00 4.20 4.10 low observation
expect_reject bad_math "$TMP_DIR/bad-math.tsv"
{ printf '%s\n' "$V2_HEADER"; tail -n 1 "$V2"; tail -n 1 "$V2"; } >"$TMP_DIR/duplicate.tsv"
expect_reject duplicate "$TMP_DIR/duplicate.tsv"
sed '1s/$/\tprofile_sha256/' "$V2" >"$TMP_DIR/secret-header.tsv"
expect_reject secret_header "$TMP_DIR/secret-header.tsv"
printf 'CFIP_ROUTER_CANARY_MIN_MBPS=3.4\n' >"$TMP_DIR/unsafe.env"
CONFIG_FILE="$TMP_DIR/unsafe.env" expect_reject unsafe_threshold "$V2"

printf '%s\n' "$V2_HEADER" >"$TMP_DIR/empty.tsv"
bash "$SCRIPT" import "$TMP_DIR/empty.tsv" | grep -q 'count=0; staging only'
[ "$(wc -l < "$STAGED")" -eq 1 ] || { echo "empty staging queue must contain only header" >&2; exit 1; }

HISTORY="$APP_DIR/router-candidate-canary-history.tsv"
QUALIFIED="$APP_DIR/router-candidate-competition-qualified.tsv"
printf 'observed_at\tcandidate_ip\tsource_export_epoch\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tbytes1\tbytes2\tstatus\tpath_mode\n' >"$HISTORY"
add_history() {
  printf '%s\t104.17.1.10\t%s\t%s\t%s\t%s\t%s\t200\t200\t20000000\t20000000\t%s\trouter_isolated_xray\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" >>"$HISTORY"
}
add_history "$(date -d '5 days ago' '+%F 03:40:00')" "$((NOW-432000))" 4.10 4.00 4.00 4.05 pass
add_history "$(date -d '4 days ago' '+%F 03:40:00')" "$((NOW-345600))" 4.20 4.10 4.10 4.15 pass
add_history "$(date -d '3 days ago' '+%F 03:40:00')" "$((NOW-259200))" 3.40 3.30 3.30 3.35 low
add_history "$(date -d '2 days ago' '+%F 03:40:00')" "$((NOW-172000))" 4.10 4.00 4.00 4.05 pass
add_history "$(date -d '1 day ago' '+%F 03:40:00')" "$((NOW-86000))" 4.20 4.10 4.10 4.15 pass
bash "$SCRIPT" qualify | grep -q 'competition_qualified_count=0'
add_history "$(date '+%F 03:40:00')" "$NOW" 4.30 4.20 4.20 4.25 pass
bash "$SCRIPT" qualify | grep -q 'competition_qualified_count=1'
awk -F '\t' '$1=="104.17.1.10" && $2==3 && $3==3 && $4==4.00 && $7=="competition_qualified" {ok=1} END{exit ok?0:1}' "$QUALIFIED" \
  || { echo "consecutive three-day qualification failed" >&2; exit 1; }

PRIMARY_HISTORY="$APP_DIR/router-primary-canary-history.tsv"
PRIMARY_QUALIFIED="$APP_DIR/router-primary-baseline-qualified.tsv"
printf 'observed_at\tcandidate_ip\tsource_export_epoch\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tbytes1\tbytes2\tstatus\tpath_mode\n' >"$PRIMARY_HISTORY"
add_primary_history() {
  printf '%s\t104.17.2.20\t%s\t%s\t%s\t%s\t%s\t200\t200\t20000000\t20000000\t%s\trouter_primary_isolated_xray\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" >>"$PRIMARY_HISTORY"
}
add_primary_history "$(date -d '2 days ago' '+%F 04:20:00')" "$((NOW-172000))" 4.30 4.20 4.20 4.25 pass
add_primary_history "$(date -d '1 day ago' '+%F 04:20:00')" "$((NOW-86000))" 4.40 4.30 4.30 4.35 pass
bash "$SCRIPT" primary-qualify | grep -q 'primary_baseline_qualified_count=0'
add_primary_history "$(date '+%F 04:20:00')" "$NOW" 4.50 4.40 4.40 4.45 pass
bash "$SCRIPT" primary-qualify | grep -q 'primary_baseline_qualified_count=1'
awk -F '\t' '$1=="104.17.2.20" && $2==3 && $3==3 && $4==4.20 && $7=="primary_baseline_qualified" && $8=="router_primary_isolated_xray" {ok=1} END{exit ok?0:1}' "$PRIMARY_QUALIFIED" \
  || { echo "primary three-day baseline qualification failed" >&2; exit 1; }

printf 'CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS=3.9\n' >"$TMP_DIR/unsafe-primary.env"
if CONFIG_FILE="$TMP_DIR/unsafe-primary.env" bash "$SCRIPT" primary-qualify >"$TMP_DIR/unsafe-primary.out" 2>&1; then
  echo "primary threshold below 4.0 MB/s was accepted" >&2; exit 1
fi
if bash "$SCRIPT" primary-canary 203.0.113.9 >"$TMP_DIR/non-cf-primary.out" 2>&1; then
  echo "non-Cloudflare primary canary target was accepted" >&2; exit 1
fi

if grep -Eq 'passwall (restart|stop)|/etc/init.d/passwall|uci (set|commit)|api.cloudflare.com' "$SCRIPT"; then
  echo "candidate gate contains forbidden production mutation" >&2; exit 1
fi

echo "router candidate gate test passed"