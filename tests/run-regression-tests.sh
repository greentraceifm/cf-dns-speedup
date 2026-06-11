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
pass "champion lifecycle fields are generated consistently"

echo "all regression tests passed"
