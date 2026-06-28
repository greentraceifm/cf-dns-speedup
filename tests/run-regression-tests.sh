#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/cf-dns-speedup.sh"
FIXTURES="$ROOT_DIR/tests/fixtures"
TMP_DIR="${TMPDIR:-/tmp}/cf-dns-speedup-tests.$$"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "not ok - $*" >&2
  exit 1
}

pass() {
  echo "ok - $*"
}

mkdir -p "$TMP_DIR"

MAIN_LINE="$(grep -n '^main ' "$SCRIPT" | tail -n 1 | cut -d: -f1)"
[ -n "$MAIN_LINE" ] || fail "cannot find main entrypoint"
head -n "$((MAIN_LINE - 1))" "$SCRIPT" > "$TMP_DIR/lib.sh"

APP_DIR="$TMP_DIR" . "$TMP_DIR/lib.sh"
. "$ROOT_DIR/lib/champion-pool.sh"

APP_DIR="$TMP_DIR"
OBSERVATION_HISTORY_FILE="$TMP_DIR/observation-history.tsv"
STABILITY_RESULT_FILE="$TMP_DIR/result.stability.tsv"
EXPOSED_SLOT_GUARD_STATE_FILE="$TMP_DIR/exposed-slot-guard.tsv"
EMERGENCY_REFRESH_REPORT_FILE="$TMP_DIR/emergency-refresh.latest.tsv"
EMERGENCY_REFRESH_VALIDATE_FILE="$TMP_DIR/emergency-refresh.validate.tsv"
CHAMPION_POOL_FILE="$TMP_DIR/champion-pool.tsv"
CHAMPION_LIFECYCLE_AUDIT_FILE="$TMP_DIR/champion-lifecycle-audit.tsv"

CFST_DUAL_POOL_MODE=1
CFST_STABLE_SLOT_MODE=1
CFST_PRIMARY_SAFE_MODE=1
CFST_STABLE_SLOT_COUNT=3
CFST_RESULT_COUNT=5
CFST_STABLE_SLOT_MIN_SPEED=8
CFST_PRIMARY_MIN_SPEED=8
CFST_STABLE_SLOT_FALLBACK_MIN_SPEED=6.5
CFST_PRIMARY_FALLBACK_MIN_SPEED=6.5
CFST_STABLE_SLOT_PREFER_REGEX='^104\.17\.'
CFST_PRIMARY_PREFER_REGEX='^104\.17\.'
CFST_STABLE_SLOT_AVOID_REGEX='^(104\.20\.|104\.26\.|172\.67\.)'
CFST_PRIMARY_AVOID_REGEX='^(104\.20\.|104\.26\.|172\.67\.)'
CFST_STABLE_SLOT_ALLOW_CHALLENGER=0
CFST_STABLE_SLOT_ALLOW_AVOID=0
CFST_PRIMARY_ALLOW_CHALLENGER=0
CFST_PRIMARY_QUORUM_MODE=1
CFST_PRIMARY_QUORUM_MIN_OBSERVATIONS=2
CFST_PRIMARY_QUORUM_RECENT_PASSES=2
CFST_PRIMARY_DEGRADE_PROTECTION=1
CFST_PRIMARY_DEGRADE_MIN_SPEED=2
CFST_PRIMARY_GUARD_ENFORCE=1
CFST_EXPOSED_SLOT_GUARD=1
CFST_EXPOSED_SLOT_MIN_SPEED=6.5
CFST_EXPOSED_SLOT_BLOCK_TTL_SECONDS=43200
CFST_GUARD_REPAIR_APPLY=0
CFST_GUARD_REPAIR_STABLE_MIRROR=1
CFST_OBSERVE_GUARD_REPAIR_REPORT=1
CFST_OBSERVE_GUARD_REPAIR_APPLY=0
CFST_OBSERVE_GUARD_REPAIR_MAX_UPDATES=2
CFST_EMERGENCY_REFRESH=1
CFST_EMERGENCY_REFRESH_APPLY=0
CFST_OBSERVE_EMERGENCY_REFRESH_APPLY=0
CFST_EMERGENCY_REFRESH_PRIMARY_MAX_MIN_SPEED=2
CFST_EMERGENCY_REFRESH_MIN_SPEED=6.5
CFST_EMERGENCY_REFRESH_CANDIDATES=5
CFST_EMERGENCY_REFRESH_ROUNDS=2
CFST_EMERGENCY_REFRESH_MIN_PASSED_SLOTS=3
CFST_EMERGENCY_REFRESH_MAX_UPDATES=5
CFST_OBSERVATION_RECENT_WINDOW=2
CFST_OBSERVATION_STALE_LOW_COUNT=2
CFST_OBSERVATION_STABLE_MAX_LOW_COUNT=0
CFST_STABILITY_TEST_ROUNDS=2
CFST_CHAMPION_POOL=1
CFST_CHAMPION_POOL_SIZE=10
CFST_DEGRADE_MIN_SPEED=2
CFST_CHAMPION_FAIL_MIN_SPEED=8
CFST_FAIL_EVICT_COUNT=3

cp "$FIXTURES/dual-pool-observation-history.tsv" "$OBSERVATION_HISTORY_FILE"
cp "$FIXTURES/dual-pool-stability-results.tsv" "$STABILITY_RESULT_FILE"

tail -n +2 "$STABILITY_RESULT_FILE" \
  | sort_stability_results \
  | apply_dual_pool_slots \
  | promote_primary_safe_candidate \
  | promote_stable_slots > "$TMP_DIR/selected.tsv"

FIRST_IP="$(awk -F '\t' 'NR == 1 {print $1}' "$TMP_DIR/selected.tsv")"
[ "$FIRST_IP" = "104.17.10.1" ] || fail "stable preferred IP should be first, got $FIRST_IP"

TOP3="$(awk -F '\t' 'NR <= 3 {print $1}' "$TMP_DIR/selected.tsv")"
SELECTED_COUNT="$(wc -l < "$TMP_DIR/selected.tsv" | tr -d ' ')"
[ "$SELECTED_COUNT" = "5" ] || fail "selector should preserve full result count, got $SELECTED_COUNT"
echo "$TOP3" | grep -q '^104\.26\.2\.86$' && fail "stale IP entered primary stable slots"
echo "$TOP3" | grep -q '^172\.67\.76\.149$' && fail "avoid-family challenger entered primary stable slots"
echo "$TOP3" | grep -q '^104\.17\.200\.1$' && fail "unobserved challenger entered primary stable slots"
echo "$TOP3" | grep -q '^104\.17\.201\.1$' && fail "single-observation IP entered primary stable slots"
pass "dual-pool keeps stale IP out of primary slots"

ORIGINAL_STABILITY_RESULT_FILE="$STABILITY_RESULT_FILE"
GUARDED_STABILITY_RESULT_FILE="$TMP_DIR/guarded-selected.tsv"
{
  printf 'ip\tlatency_ms\tcfst_speed_mbps\tmin_speed_mbps\tavg_speed_mbps\tok_rounds\tsource\n'
  cat "$TMP_DIR/selected.tsv"
} > "$GUARDED_STABILITY_RESULT_FILE"
STABILITY_RESULT_FILE="$GUARDED_STABILITY_RESULT_FILE"
VALIDATE_RESULT_FILE="$TMP_DIR/validate-current.latest.tsv"
awk -F '\t' '
  BEGIN {print "ip\tprevious_latency_ms\tprevious_speed_mbps\tmin_speed_mbps\tavg_speed_mbps\tok_rounds"}
  {
    min = NR <= 3 ? 8.00 : 0.25
    avg = NR <= 3 ? 8.50 : 0.40
    ok = 2
    printf "%s\t0\t0\t%.2f\t%.2f\t%d\n", $1, min, avg, ok
  }
' "$TMP_DIR/selected.tsv" > "$VALIDATE_RESULT_FILE"
DNS_SLOT4="$(best_ip_list | awk 'NR == 4 {print $1}')"
DNS_SLOT5="$(best_ip_list | awk 'NR == 5 {print $1}')"
[ "$DNS_SLOT4" = "104.17.10.1" ] || fail "exposed slot guard should mirror slot 4 to first stable IP, got $DNS_SLOT4"
[ "$DNS_SLOT5" = "104.17.10.2" ] || fail "exposed slot guard should mirror slot 5 to second stable IP, got $DNS_SLOT5"
print_exposed_slot_guard | awk -F '\t' 'NR > 1 && $5 == "mirrored" {mirrored++} END {exit mirrored >= 2 ? 0 : 1}' \
  || fail "exposed slot guard should report mirrored competitive slots"
refresh_exposed_slot_guard_state
awk -F '\t' '$3 == "172.67.76.149" && $5 == "blocked" {found=1} END {exit found ? 0 : 1}' "$EXPOSED_SLOT_GUARD_STATE_FILE" \
  || fail "exposed slot guard state did not remember degraded competitive IP"
cat > "$VALIDATE_RESULT_FILE" <<'EOF'
ip	previous_latency_ms	previous_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds
104.17.10.1	0	0	8.00	8.50	2
104.17.10.2	0	0	8.00	8.50	2
104.17.10.3	0	0	8.00	8.50	2
EOF
DNS_SLOT4_AFTER_REPAIR="$(best_ip_list | awk 'NR == 4 {print $1}')"
[ "$DNS_SLOT4_AFTER_REPAIR" = "104.17.10.1" ] || fail "exposed slot guard state should keep degraded IP mirrored after DNS repair, got $DNS_SLOT4_AFTER_REPAIR"
CF_RECORD_NAMES="auto.example.test auto1.example.test auto2.example.test auto3.example.test auto4.example.test"
CFST_GUARD_REPAIR_CURRENT_FILE="$TMP_DIR/current-dns.tsv"
cat > "$CFST_GUARD_REPAIR_CURRENT_FILE" <<'EOF'
name	ip
auto.example.test	104.17.10.1
auto1.example.test	104.17.10.2
auto2.example.test	104.17.10.3
auto3.example.test	172.67.76.149
auto4.example.test	104.26.2.86
EOF
guard_repair_plan_rows > "$TMP_DIR/guard-repair-plan.tsv"
awk -F '\t' '$1 == "auto3.example.test" && $2 == "172.67.76.149" && $3 == "104.17.10.1" && $4 == "update" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/guard-repair-plan.tsv" \
  || fail "guard-repair should plan auto3 update to mirrored stable slot"
awk -F '\t' '$1 == "auto4.example.test" && $2 == "104.26.2.86" && $3 == "104.17.10.2" && $4 == "update" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/guard-repair-plan.tsv" \
  || fail "guard-repair should plan auto4 update to mirrored stable slot"
cp "$TMP_DIR/guard-repair-plan.tsv" "$GUARD_REPAIR_REPORT_FILE"
[ "$(guard_repair_update_count)" = "2" ] || fail "guard-repair update count should be 2"
check_cloudflare_auth() {
  :
}
upsert_single_dns_record() {
  printf '%s\t%s\n' "$1" "$2" >> "$TMP_DIR/applied-dns.tsv"
}
apply_guard_repair_report_updates
awk -F '\t' '$1 == "auto3.example.test" && $2 == "104.17.10.1" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/applied-dns.tsv" \
  || fail "guard-repair auto apply should update auto3 to stable mirror"
awk -F '\t' '$1 == "auto4.example.test" && $2 == "104.17.10.2" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/applied-dns.tsv" \
  || fail "guard-repair auto apply should update auto4 to stable mirror"
awk -F '\t' '$1 == "auto.example.test" || $1 == "auto1.example.test" || $1 == "auto2.example.test" {bad=1} END {exit bad ? 1 : 0}' "$TMP_DIR/applied-dns.tsv" \
  || fail "guard-repair auto apply should not rewrite primary slots"

cat > "$VALIDATE_RESULT_FILE" <<'EOF'
ip	previous_latency_ms	previous_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds
104.26.10.1	0	0	16.00	16.50	2
104.26.10.2	0	0	16.00	16.50	2
172.67.10.3	0	0	16.00	16.50	2
104.20.10.4	0	0	0.10	0.20	2
172.67.10.5	0	0	0.10	0.20	2
EOF
cat > "$STABILITY_RESULT_FILE" <<'EOF'
ip	latency_ms	cfst_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds	source
104.26.10.1	0	16.00	16.00	16.50	2	champion
104.26.10.2	0	16.00	16.00	16.50	2	champion
172.67.10.3	0	16.00	16.00	16.50	2	champion
104.20.10.4	0	16.00	0.10	0.20	2	champion
172.67.10.5	0	16.00	0.10	0.20	2	champion
EOF
cat > "$CFST_GUARD_REPAIR_CURRENT_FILE" <<'EOF'
name	ip
auto.example.test	104.17.10.1
auto1.example.test	104.17.10.2
auto2.example.test	104.17.10.3
auto3.example.test	104.20.10.4
auto4.example.test	172.67.10.5
EOF
guard_repair_plan_rows > "$TMP_DIR/guard-repair-failed-run-plan.tsv"
awk -F '\t' '$1 == "auto.example.test" && $4 == "ok" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/guard-repair-failed-run-plan.tsv" \
  || fail "guard-repair should not rewrite stable primary slot after failed run"
awk -F '\t' '$1 == "auto3.example.test" && $2 == "104.20.10.4" && $3 == "104.17.10.1" && $4 == "update" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/guard-repair-failed-run-plan.tsv" \
  || fail "guard-repair should mirror degraded auto3 to current stable primary after failed run"
awk -F '\t' '$1 == "auto4.example.test" && $2 == "172.67.10.5" && $3 == "104.17.10.2" && $4 == "update" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/guard-repair-failed-run-plan.tsv" \
  || fail "guard-repair should mirror degraded auto4 to current stable primary after failed run"
STABILITY_RESULT_FILE="$ORIGINAL_STABILITY_RESULT_FILE"
pass "exposed slot guard mirrors degraded competitive slots"

cat > "$VALIDATE_RESULT_FILE" <<'EOF'
ip	previous_latency_ms	previous_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds
104.17.10.1	0	0	0.30	0.40	2
104.17.10.2	0	0	0.40	0.50	2
104.17.10.3	0	0	0.50	0.60	2
104.17.10.1	0	0	0.30	0.40	2
104.17.10.2	0	0	0.40	0.50	2
EOF
cat > "$STABILITY_RESULT_FILE" <<'EOF'
ip	latency_ms	cfst_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds	source
104.26.20.1	0	18.00	18.00	18.00	2	champion
104.26.20.2	0	17.00	17.00	17.00	2	champion
172.67.20.3	0	16.00	16.00	16.00	2	champion
104.20.20.4	0	15.00	15.00	15.00	2	champion
172.67.20.5	0	14.00	14.00	14.00	2	champion
EOF
download_speed_bps() {
  case "$2" in
    104.26.20.1) echo 18874368 ;;
    104.26.20.2) echo 17825792 ;;
    172.67.20.3) echo 16777216 ;;
    104.20.20.4) echo 1048576 ;;
    *) echo 0 ;;
  esac
}
CFST_URL="https://example.test/20mb.bin"
CFST_PORT=443
CFST_STABILITY_CONNECT_TIMEOUT=1
CFST_STABILITY_TIMEOUT=1
emergency_refresh_primary_degraded || fail "emergency refresh should trigger when all primary slots are degraded"
emergency_refresh_validate_candidates
[ "$(emergency_refresh_passed_count)" = "3" ] || fail "emergency refresh should find three freshly passing candidates"
emergency_refresh_plan_rows > "$TMP_DIR/emergency-refresh-plan.tsv"
awk -F '\t' '$1 == "auto.example.test" && $3 == "104.26.20.1" && $4 == "update" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/emergency-refresh-plan.tsv" \
  || fail "emergency refresh should promote freshly validated candidate to auto"
awk -F '\t' '$1 == "auto3.example.test" && $3 == "104.26.20.1" && $4 == "update" {found=1} END {exit found ? 0 : 1}' "$TMP_DIR/emergency-refresh-plan.tsv" \
  || fail "emergency refresh should mirror exposed slots to refreshed primary winners"
cp "$TMP_DIR/emergency-refresh-plan.tsv" "$EMERGENCY_REFRESH_REPORT_FILE"
[ "$(emergency_refresh_update_count)" = "5" ] || fail "emergency refresh should plan bounded five-slot replacement"
awk -F '\t' 'BEGIN {OFS="\t"} NR == 1 {print; next} {if (NR == 2) $4="2.10"; print}' "$VALIDATE_RESULT_FILE" > "$TMP_DIR/validate-current.not-all-bad.tsv"
mv "$TMP_DIR/validate-current.not-all-bad.tsv" "$VALIDATE_RESULT_FILE"
if emergency_refresh_primary_degraded; then
  fail "emergency refresh should not trigger while any primary slot is above trigger"
fi
cp "$FIXTURES/dual-pool-stability-results.tsv" "$ORIGINAL_STABILITY_RESULT_FILE"
STABILITY_RESULT_FILE="$ORIGINAL_STABILITY_RESULT_FILE"
pass "emergency refresh only promotes freshly validated candidates during full primary degradation"

GUARD_STATUS="$(print_primary_slot_guard | awk -F '\t' '$2 == "104.26.2.86" {print $6}')"
[ "$GUARD_STATUS" = "degraded" ] || fail "primary-slot guard should report degraded IP, got ${GUARD_STATUS:-missing}"
pass "primary-slot guard reports degraded primary slots"

BAD_STABILITY_RESULT_FILE="$TMP_DIR/bad-primary.tsv"
cat > "$BAD_STABILITY_RESULT_FILE" <<'EOF'
ip	latency_ms	cfst_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds	source
104.26.2.86	80	55.00	0.23	0.30	0	champion
104.17.10.1	85	9.50	9.40	9.60	2	observation
104.17.10.2	90	9.00	8.90	9.20	2	observation
EOF
ORIGINAL_STABILITY_RESULT_FILE="$STABILITY_RESULT_FILE"
STABILITY_RESULT_FILE="$BAD_STABILITY_RESULT_FILE"
if ( assert_primary_slot_guard >/dev/null 2>&1 ); then
  fail "primary guard should block degraded primary candidate"
fi
STABILITY_RESULT_FILE="$ORIGINAL_STABILITY_RESULT_FILE"
pass "primary-slot guard blocks unsafe DNS update"

SHORT_STABILITY_RESULT_FILE="$TMP_DIR/short-primary.tsv"
cat > "$SHORT_STABILITY_RESULT_FILE" <<'EOF'
ip	latency_ms	cfst_speed_mbps	min_speed_mbps	avg_speed_mbps	ok_rounds	source
104.17.10.1	85	9.50	9.40	9.60	2	observation
104.17.10.2	90	9.00	8.90	9.20	2	observation
EOF
STABILITY_RESULT_FILE="$SHORT_STABILITY_RESULT_FILE"
MISSING_STATUS="$(print_primary_slot_guard | awk -F '\t' '$2 == "missing" {print $6; exit}')"
[ "$MISSING_STATUS" = "missing" ] || fail "primary guard should report missing primary slot, got ${MISSING_STATUS:-missing-report-absent}"
if ( assert_primary_slot_guard >/dev/null 2>&1 ); then
  fail "primary guard should block missing primary slot"
fi
STABILITY_RESULT_FILE="$ORIGINAL_STABILITY_RESULT_FILE"
pass "primary-slot guard blocks missing primary slots"

cp "$FIXTURES/lifecycle-champion-pool.tsv" "$CHAMPION_POOL_FILE"
update_champion_pool >/dev/null

HEADER_FIELDS="$(awk -F '\t' 'NR == 1 {print NF}' "$CHAMPION_POOL_FILE")"
DATA_FIELDS="$(awk -F '\t' 'NR == 2 {print NF}' "$CHAMPION_POOL_FILE")"
[ "$HEADER_FIELDS" = "$DATA_FIELDS" ] || fail "champion-pool header/data field mismatch: $HEADER_FIELDS/$DATA_FIELDS"

awk -F '\t' '$1 == "104.17.10.1" && $13 == "stable" && $18 == "1" {found=1} END {exit found ? 0 : 1}' "$CHAMPION_POOL_FILE" \
  || fail "stable IP did not retain lifecycle state and promotion_ready"
awk -F '\t' '$1 == "104.17.10.4" && $9 == "stable" && $13 == "stable" && $18 == "1" {found=1} END {exit found ? 0 : 1}' "$CHAMPION_POOL_FILE" \
  || fail "fallback-quorum stable IP was not promotion_ready"
grep -q '^print_champion_summary()' "$SCRIPT" || fail "champion summary function is missing"
grep -q 'guard-repair-dry-run' "$SCRIPT" || fail "observe-current guard-repair dry-run report is missing"
grep -q 'if \[ "$PUSH_MODE" = "domain" \]; then' "$SCRIPT" || fail "primary guard should only gate DNS update mode"
pass "champion lifecycle fields are generated consistently"

echo "all regression tests passed"
