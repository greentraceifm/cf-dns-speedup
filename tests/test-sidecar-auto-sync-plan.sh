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

PRIMARY_QUALIFIED="$TEST_TMP/primary-qualified.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.137.93\t3\t3\t4.00\t4.10\t2026-07-29 04:20:00\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.153.15\t3\t3\t4.60\t4.70\t2026-07-29 04:21:00\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.134.190\t3\t3\t4.20\t4.30\t2026-07-29 04:22:00\tprimary_baseline_qualified\trouter_primary_isolated_xray\n' >"$PRIMARY_QUALIFIED"
PROMOTION_QUALIFIED="$TEST_TMP/promotion-qualified.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.1.10\t3\t3\t5.10\t5.20\t2026-07-29 04:16:00\tcompetition_qualified\trouter_isolated_xray\n104.17.1.11\t3\t3\t4.90\t5.00\t2026-07-29 04:17:00\tcompetition_qualified\trouter_isolated_xray\n' >"$PROMOTION_QUALIFIED"
PROMOTION_CURRENT="$TEST_TMP/promotion-current.tsv"
printf 'auto.example.test\t104.17.137.93\nauto1.example.test\t104.17.153.15\nauto2.example.test\t104.17.134.190\nauto3.example.test\t104.17.1.10\nauto4.example.test\t104.17.1.11\n' >"$PROMOTION_CURRENT"
PRIMARY_TARGETS="$TEST_TMP/primary-targets.tsv"
build_primary_targets "$PROMOTION_CURRENT" "$PRIMARY_QUALIFIED" "$PROMOTION_QUALIFIED" "$PRIMARY_TARGETS"
[ "$PRIMARY_BASELINE_READY" -eq 1 ] || { echo "complete primary baseline was not accepted" >&2; exit 1; }
awk -F '\t' '$1=="auto.example.test" && $2=="104.17.1.10" && $5=="challenger"{a=1} $1=="auto1.example.test" && $2=="104.17.153.15"{b=1} $1=="auto2.example.test" && $2=="104.17.134.190"{c=1} END{exit(a&&b&&c)?0:1}' "$PRIMARY_TARGETS" \
  || { echo "primary ranking or 25 percent promotion is wrong" >&2; exit 1; }
choose_pending_target "$PROMOTION_CURRENT" "$PRIMARY_TARGETS" "$PENDING"
awk -F '\t' 'NR==1 && $1=="auto.example.test" && $2=="104.17.1.10" && $3=="104.17.137.93"{ok=1} END{exit ok?0:1}' "$PENDING" \
  || { echo "primary plan did not select exactly the first mismatched record" >&2; exit 1; }

head -n 1 "$PRIMARY_QUALIFIED" >"$TEST_TMP/empty-primary-qualified.tsv"
build_primary_targets "$PROMOTION_CURRENT" "$TEST_TMP/empty-primary-qualified.tsv" "$PROMOTION_QUALIFIED" "$PRIMARY_TARGETS"
[ "$PRIMARY_BASELINE_READY" -eq 0 ] && [ ! -s "$PRIMARY_TARGETS" ] \
  || { echo "incomplete primary baseline did not fail closed" >&2; exit 1; }

sed 's/104.17.1.10\t3\t3\t5.10/104.17.1.10\t3\t3\t4.99/' "$PROMOTION_QUALIFIED" >"$TEST_TMP/below-improvement.tsv"
build_primary_targets "$PROMOTION_CURRENT" "$PRIMARY_QUALIFIED" "$TEST_TMP/below-improvement.tsv" "$PRIMARY_TARGETS"
if grep -q $'\t104.17.1.10\t' "$PRIMARY_TARGETS"; then
  echo "challenger below 25 percent improvement entered primary targets" >&2; exit 1
fi
build_primary_targets "$CURRENT" "$PRIMARY_QUALIFIED" "$PROMOTION_QUALIFIED" "$PRIMARY_TARGETS"
if grep -q $'\t104.17.1.10\t' "$PRIMARY_TARGETS"; then
  echo "challenger outside auto3/auto4 entered primary targets" >&2; exit 1
fi

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
sed 's/PRIMARY_PROMOTION_APPLY=0/PRIMARY_PROMOTION_APPLY=1/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/enabled.env"
if ! (AUTO_CONFIG_FILE="$TEST_TMP/enabled.env" load_config >/dev/null 2>&1); then
  echo "authorized primary promotion apply value was rejected" >&2; exit 1
fi
sed 's/PRIMARY_PROMOTION_APPLY=0/PRIMARY_PROMOTION_APPLY=2/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/unsafe.env"
if (AUTO_CONFIG_FILE="$TEST_TMP/unsafe.env" load_config >/dev/null 2>&1); then
  echo "invalid primary promotion apply value was accepted" >&2; exit 1
fi
sed 's/MAX_CANARIES=3/MAX_CANARIES=4/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/too-many.env"
if (AUTO_CONFIG_FILE="$TEST_TMP/too-many.env" load_config >/dev/null 2>&1); then
  echo "more than three canaries were accepted" >&2; exit 1
fi
sed 's/MIN_MBPS=3.5/MIN_MBPS=3.4/' "$AUTO_CONFIG_FILE" >"$TEST_TMP/below-floor.env"
if (AUTO_CONFIG_FILE="$TEST_TMP/below-floor.env" load_config >/dev/null 2>&1); then
  echo "competition threshold below 3.5 MB/s was accepted" >&2; exit 1
fi

CF_API_TOKEN=dummy
CF_ZONE_ID=dummy
CF_REQUEST_TEST_OUTPUT="$TEST_TMP/cf-response.json"
CF_REQUEST_TEST_COUNTER="$TEST_TMP/curl-attempts"
: >"$CF_REQUEST_TEST_COUNTER"
curl() {
  local attempts
  cat >/dev/null
  printf 'x\n' >>"$CF_REQUEST_TEST_COUNTER"
  attempts="$(wc -l <"$CF_REQUEST_TEST_COUNTER")"
  if [ "$attempts" -lt 3 ]; then
    return 6
  fi
  printf '{"success":true,"result":[{"content":"104.17.1.10"}]}\n' >"$CF_REQUEST_TEST_OUTPUT"
  printf '200'
}
sleep() { :; }
cf_get_record auto.example.test "$CF_REQUEST_TEST_OUTPUT"
[ "$(wc -l <"$CF_REQUEST_TEST_COUNTER")" -eq 3 ] \
  || { echo "Cloudflare transport retry count is wrong" >&2; exit 1; }

CF_REQUEST_TEST_JQ_MARKER="$TEST_TMP/jq-after-failure"
cf_request() { return 1; }
jq() { : >"$CF_REQUEST_TEST_JQ_MARKER"; return 0; }
if cf_get_record auto.example.test "$TEST_TMP/missing-response.json"; then
  echo "Cloudflare GET failure was not propagated" >&2; exit 1
fi
[ ! -e "$CF_REQUEST_TEST_JQ_MARKER" ] \
  || { echo "jq ran after a failed Cloudflare request" >&2; exit 1; }

echo "sidecar auto sync plan test passed"