#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
# shellcheck disable=SC1090
. "$ROOT/sidecar-auto-sync.sh"
trap 'rm -rf "$TEST_TMP"' EXIT
APP_DIR="$TEST_TMP/app"
STAGING_FILE="$APP_DIR/candidate-staging/sidecar-candidates.latest.tsv"
QUALIFIED_FILE="$APP_DIR/router-candidate-competition-qualified.tsv"
CFIP_AUTO_SYNC_RECORDS="auto3.example.test auto4.example.test"
CFIP_AUTO_SYNC_PRIMARY_RECORDS="auto.example.test auto1.example.test auto2.example.test"
mkdir -p "$(dirname "$STAGING_FILE")"
cat >"$STAGING_FILE" <<'DATA'
schema_version	exported_epoch	observed_at	candidate_ip	direct_MBps	round1_MBps	round2_MBps	min_MBps	avg_MBps	http1	http2	status	path_mode	candidate_tier
cfip-sidecar-candidates-v2	1785000000	2026-07-29 03:30:00	104.17.1.10	9.00	4.70	4.60	4.60	4.65	200	200	low	sidecar_proxy	observation
cfip-sidecar-candidates-v2	1785000000	2026-07-29 03:31:00	104.17.1.11	9.00	4.30	4.20	4.20	4.25	200	200	low	sidecar_proxy	observation
DATA
cat >"$QUALIFIED_FILE" <<'DATA'
candidate_ip	consecutive_pass_days	pass_exports	window_min_MBps	window_avg_MBps	last_observed_at	status	path_mode
104.17.1.11	5	5	4.20	4.40	2026-07-29 04:15:00	competition_qualified	router_isolated_xray
104.17.1.10	3	3	4.60	4.70	2026-07-29 04:16:00	competition_qualified	router_isolated_xray
DATA
CURRENT="$TEST_TMP/current.tsv"
cat >"$CURRENT" <<'DATA'
auto.example.test	104.17.137.93
auto1.example.test	104.17.153.15
auto2.example.test	104.17.134.190
auto3.example.test	104.17.137.93
auto4.example.test	104.17.153.15
DATA
QUALIFIED="$TEST_TMP/qualified.tsv"; TARGETS="$TEST_TMP/targets.tsv"; PENDING="$TEST_TMP/pending.tsv"
choose_qualified_candidates "$QUALIFIED"
[ "$(awk -F '\t' 'NR==1{print $1}' "$QUALIFIED")" = 104.17.1.10 ] || { echo "minimum-speed ranking is wrong" >&2; exit 1; }
build_competition_targets "$CURRENT" "$QUALIFIED" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.1.10" && $5=="challenger"{a=1} $1=="auto4.example.test" && $2=="104.17.1.11"{b=1} END{exit(a&&b)?0:1}' "$TARGETS"
if grep -Eq '^auto(1|2)?\.example\.test\t' "$TARGETS"; then echo "primary record entered competition write plan" >&2; exit 1; fi
choose_pending_target "$CURRENT" "$TARGETS" "$PENDING"
awk -F '\t' 'NR==1 && $1=="auto3.example.test" && $2=="104.17.1.10" && $3=="104.17.137.93"{ok=1} END{exit ok?0:1}' "$PENDING"

head -n 1 "$QUALIFIED" >"$TEST_TMP/one-qualified.tsv"
build_competition_targets "$CURRENT" "$TEST_TMP/one-qualified.tsv" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.1.10"{a=1} $1=="auto4.example.test" && $2=="104.17.153.15" && $5=="stable_mirror"{b=1} END{exit(a&&b)?0:1}' "$TARGETS"

: >"$TEST_TMP/no-qualified.tsv"
build_competition_targets "$CURRENT" "$TEST_TMP/no-qualified.tsv" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.137.93" && $5=="stable_mirror"{a=1} $1=="auto4.example.test" && $2=="104.17.153.15" && $5=="stable_mirror"{b=1} END{exit(a&&b)?0:1}' "$TARGETS"

CONFIG_FILE="$TEST_TMP/config.env"; AUTO_CONFIG_FILE="$TEST_TMP/auto.env"
cat >"$CONFIG_FILE" <<'DATA'
CF_API_TOKEN=dummy
CF_ZONE_ID=dummy
CF_RECORD_NAMES="auto.example.test auto1.example.test auto2.example.test auto3.example.test auto4.example.test"
DATA
cat >"$AUTO_CONFIG_FILE" <<'DATA'
CFIP_AUTO_SYNC_APPLY=0
CFIP_AUTO_SYNC_RECORDS="auto3.example.test auto4.example.test"
CFIP_AUTO_SYNC_PRIMARY_RECORDS="auto.example.test auto1.example.test auto2.example.test"
CFIP_AUTO_SYNC_MAX_CANARIES=3
CFIP_AUTO_SYNC_MIN_MBPS=3.5
CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS=4.0
CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT=25
CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY=0
DATA
load_config
sed 's/PRIMARY_PROMOTION_APPLY=0/PRIMARY_PROMOTION_APPLY=1/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/unsafe.env"
if (AUTO_CONFIG_FILE="$TEST_TMP/unsafe.env" load_config >/dev/null 2>&1); then
  echo "primary promotion apply was not fail-closed" >&2; exit 1
fi
sed 's/MAX_CANARIES=3/MAX_CANARIES=4/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/too-many.env"
if (AUTO_CONFIG_FILE="$TEST_TMP/too-many.env" load_config >/dev/null 2>&1); then
  echo "more than three canaries were accepted" >&2; exit 1
fi
sed 's/MIN_MBPS=3.5/MIN_MBPS=3.4/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/below-floor.env"
if (AUTO_CONFIG_FILE="$TEST_TMP/below-floor.env" load_config >/dev/null 2>&1); then
  echo "competition threshold below 3.5 MB/s was accepted" >&2; exit 1
fi

echo "sidecar auto sync plan test passed"