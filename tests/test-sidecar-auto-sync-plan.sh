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
printf '104.17.9.9\t9\t3.60\t3.90\n104.17.1.1\t3\t4.50\t4.60\n104.17.8.8\t5\t4.20\t4.70\n' \
  | rank_candidate_rows 2 >"$TEST_TMP/portable-ranking.tsv"
awk -F '\t' 'NR==1 && $1=="104.17.1.1"{a=1} NR==2 && $1=="104.17.8.8"{b=1} END{exit(a&&b)?0:1}' \
  "$TEST_TMP/portable-ranking.tsv" \
  || { echo "portable numeric ranking is wrong" >&2; exit 1; }

choose_qualified_candidates "$QUALIFIED"
[ "$(awk -F '\t' 'NR==1{print $1}' "$QUALIFIED")" = 104.17.1.10 ] || { echo "minimum-speed ranking is wrong" >&2; exit 1; }
build_competition_targets "$CURRENT" "$QUALIFIED" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.1.10" && $5=="challenger"{a=1} $1=="auto4.example.test" && $2=="104.17.1.11"{b=1} END{exit(a&&b)?0:1}' "$TARGETS"
if grep -Eq '^auto(1|2)?\.example\.test\t' "$TARGETS"; then echo "primary record entered competition write plan" >&2; exit 1; fi
choose_pending_target "$CURRENT" "$TARGETS" "$PENDING"
awk -F '\t' 'NR==1 && $1=="auto3.example.test" && $2=="104.17.1.10" && $3=="104.17.137.93"{ok=1} END{exit ok?0:1}' "$PENDING"

head -n 1 "$QUALIFIED" >"$TEST_TMP/one-qualified.tsv"
build_competition_targets "$CURRENT" "$TEST_TMP/one-qualified.tsv" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.1.10"{a=1} $1=="auto4.example.test" && $2=="104.17.137.93" && $5=="stable_mirror"{b=1} END{exit(a&&b)?0:1}' "$TARGETS"

: >"$TEST_TMP/no-qualified.tsv"
build_competition_targets "$CURRENT" "$TEST_TMP/no-qualified.tsv" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.137.93" && $5=="stable_mirror"{a=1} $1=="auto4.example.test" && $2=="104.17.153.15" && $5=="stable_mirror"{b=1} END{exit(a&&b)?0:1}' "$TARGETS"

MIRROR_DUP_CURRENT="$TEST_TMP/mirror-duplicate-current.tsv"
printf 'auto.example.test\t104.17.153.15\nauto1.example.test\t104.17.153.15\nauto2.example.test\t104.17.134.190\nauto3.example.test\t104.17.153.15\nauto4.example.test\t104.17.153.15\n' >"$MIRROR_DUP_CURRENT"
build_competition_targets "$MIRROR_DUP_CURRENT" "$TEST_TMP/no-qualified.tsv" "$TARGETS"
awk -F '\t' '$1=="auto3.example.test" && $2=="104.17.153.15" && $5=="stable_mirror"{a=1} $1=="auto4.example.test" && $2=="104.17.134.190" && $5=="stable_mirror"{b=1} END{exit(a&&b)?0:1}' "$TARGETS" \
  || { echo "stable mirror selection did not avoid duplicate primary IPs" >&2; exit 1; }

if primary_records_have_duplicates "$MIRROR_DUP_CURRENT"; then :; else
  echo "duplicate primary detector missed duplicate records" >&2; exit 1
fi

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

head -n 3 "$PRIMARY_QUALIFIED" >"$TEST_TMP/two-primary-qualified.tsv"
build_primary_targets "$PROMOTION_CURRENT" "$TEST_TMP/two-primary-qualified.tsv" "$PROMOTION_QUALIFIED" "$PRIMARY_TARGETS"
[ "$PRIMARY_BASELINE_READY" -eq 0 ] && [ ! -s "$PRIMARY_TARGETS" ] \
  || { echo "undersized primary ranking pool did not fail closed" >&2; exit 1; }

sed 's/104.17.1.10\t3\t3\t5.10/104.17.1.10\t3\t3\t4.99/' "$PROMOTION_QUALIFIED" >"$TEST_TMP/below-improvement.tsv"
build_primary_targets "$PROMOTION_CURRENT" "$PRIMARY_QUALIFIED" "$TEST_TMP/below-improvement.tsv" "$PRIMARY_TARGETS"
if grep -q $'\t104.17.1.10\t' "$PRIMARY_TARGETS"; then
  echo "challenger below 25 percent improvement entered primary targets" >&2; exit 1
fi
build_primary_targets "$CURRENT" "$PRIMARY_QUALIFIED" "$PROMOTION_QUALIFIED" "$PRIMARY_TARGETS"
if grep -q $'\t104.17.1.10\t' "$PRIMARY_TARGETS"; then
  echo "challenger outside auto3/auto4 entered primary targets" >&2; exit 1
fi

DUPLICATE_CURRENT="$TEST_TMP/duplicate-current.tsv"
printf 'auto.example.test\t104.17.153.15\nauto1.example.test\t104.17.153.15\nauto2.example.test\t104.17.134.190\nauto3.example.test\t104.17.135.183\nauto4.example.test\t104.17.153.186\n' >"$DUPLICATE_CURRENT"
DUPLICATE_PRIMARY="$TEST_TMP/duplicate-primary.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.153.15\t7\t7\t4.19\t4.32\t2026-08-19 04:16:01\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.134.190\t7\t7\t4.14\t4.40\t2026-08-19 04:16:13\tprimary_baseline_qualified\trouter_primary_isolated_xray\n' >"$DUPLICATE_PRIMARY"
DUPLICATE_COMPETITION="$TEST_TMP/duplicate-competition.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.135.183\t7\t7\t4.20\t4.38\t2026-08-19 04:15:27\tcompetition_qualified\trouter_isolated_xray\n104.17.153.186\t7\t7\t4.06\t4.33\t2026-08-19 04:15:38\tcompetition_qualified\trouter_isolated_xray\n' >"$DUPLICATE_COMPETITION"
build_primary_targets "$DUPLICATE_CURRENT" "$DUPLICATE_PRIMARY" "$DUPLICATE_COMPETITION" "$PRIMARY_TARGETS"
[ "$PRIMARY_BASELINE_READY" -eq 1 ] || { echo "duplicate primary repair was not accepted" >&2; exit 1; }
awk -F '\t' '$1=="auto.example.test" && $2=="104.17.153.15"{a=1} $1=="auto1.example.test" && $2=="104.17.135.183" && $5=="duplicate_repair"{b=1} $1=="auto2.example.test" && $2=="104.17.134.190"{c=1} END{exit(a&&b&&c)?0:1}' "$PRIMARY_TARGETS" \
  || { echo "duplicate primary repair target is wrong" >&2; exit 1; }

DUPLICATE_PRIMARY_CURRENT="$TEST_TMP/duplicate-primary-current.tsv"
printf 'auto.example.test\t104.17.153.15\nauto1.example.test\t104.17.153.15\nauto2.example.test\t104.17.134.190\nauto3.example.test\t104.17.129.81\nauto4.example.test\t104.17.153.15\n' >"$DUPLICATE_PRIMARY_CURRENT"
DUPLICATE_PRIMARY_QUALIFIED="$TEST_TMP/duplicate-primary-qualified.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.153.15\t6\t6\t4.26\t4.36\t2026-08-23 04:35:54\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.134.190\t6\t6\t4.14\t4.35\t2026-08-23 04:36:05\tprimary_baseline_qualified\trouter_primary_isolated_xray\n' >"$DUPLICATE_PRIMARY_QUALIFIED"
DUPLICATE_PRIMARY_COMPETITION="$TEST_TMP/duplicate-primary-competition.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.129.81\t3\t3\t4.27\t4.37\t2026-08-23 04:35:20\tcompetition_qualified\trouter_isolated_xray\n' >"$DUPLICATE_PRIMARY_COMPETITION"
build_primary_targets "$DUPLICATE_PRIMARY_CURRENT" "$DUPLICATE_PRIMARY_QUALIFIED" "$DUPLICATE_PRIMARY_COMPETITION" "$PRIMARY_TARGETS"
awk -F '\t' '$1=="auto.example.test" && $2=="104.17.153.15"{a=1} $1=="auto1.example.test" && $2=="104.17.129.81"{b=1} $1=="auto2.example.test" && $2=="104.17.134.190"{c=1} END{exit(a&&b&&c)?0:1}' "$PRIMARY_TARGETS" \
  || { echo "duplicate primary repair did not produce three distinct targets" >&2; exit 1; }

UNUSED_REPAIR_CURRENT="$TEST_TMP/unused-repair-current.tsv"
printf 'auto.example.test\t104.17.129.81\nauto1.example.test\t104.17.129.81\nauto2.example.test\t104.17.134.190\nauto3.example.test\t104.17.158.61\nauto4.example.test\t104.17.153.15\n' >"$UNUSED_REPAIR_CURRENT"
UNUSED_REPAIR_PRIMARY="$TEST_TMP/unused-repair-primary.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.129.81\t3\t3\t4.29\t4.33\t2026-08-27 04:36:02\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.134.190\t7\t7\t4.13\t4.36\t2026-08-27 04:36:13\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.153.15\t6\t6\t4.26\t4.40\t2026-08-26 04:35:53\tprimary_baseline_qualified\trouter_primary_isolated_xray\n' >"$UNUSED_REPAIR_PRIMARY"
UNUSED_REPAIR_COMPETITION="$TEST_TMP/unused-repair-competition.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.130.125\t7\t7\t4.14\t4.33\t2026-08-27 04:35:27\tcompetition_qualified\trouter_isolated_xray\n104.17.129.81\t4\t4\t4.27\t4.36\t2026-08-24 04:35:22\tcompetition_qualified\trouter_isolated_xray\n104.17.158.61\t3\t3\t4.23\t4.32\t2026-08-27 04:35:39\tcompetition_qualified\trouter_isolated_xray\n' >"$UNUSED_REPAIR_COMPETITION"
build_primary_targets "$UNUSED_REPAIR_CURRENT" "$UNUSED_REPAIR_PRIMARY" "$UNUSED_REPAIR_COMPETITION" "$PRIMARY_TARGETS"
awk -F '\t' '$1=="auto.example.test" && $2!=""{a=$2} $1=="auto1.example.test" && $2!=""{b=$2} $1=="auto2.example.test" && $2!=""{c=$2} END{exit(a!="" && b!="" && c!="" && a!=b && a!=c && b!=c)?0:1}' "$PRIMARY_TARGETS" \
  || { echo "duplicate repair did not produce three distinct primary targets" >&2; exit 1; }

UNSAFE_SWAP_CURRENT="$TEST_TMP/unsafe-primary-swap-current.tsv"
printf 'auto.example.test\t104.17.153.15\nauto1.example.test\t104.17.129.81\nauto2.example.test\t104.17.134.190\nauto3.example.test\t104.17.130.125\nauto4.example.test\t104.17.153.186\n' >"$UNSAFE_SWAP_CURRENT"
UNSAFE_SWAP_PRIMARY="$TEST_TMP/unsafe-primary-swap-qualified.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.153.15\t6\t6\t4.26\t4.40\t2026-08-26 04:35:53\tprimary_baseline_qualified\trouter_primary_isolated_xray\n104.17.134.190\t6\t6\t4.13\t4.38\t2026-08-26 04:36:16\tprimary_baseline_qualified\trouter_primary_isolated_xray\n' >"$UNSAFE_SWAP_PRIMARY"
UNSAFE_SWAP_COMPETITION="$TEST_TMP/unsafe-primary-swap-competition.tsv"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.129.81\t4\t4\t4.27\t4.36\t2026-08-24 04:35:22\tcompetition_qualified\trouter_isolated_xray\n104.17.130.125\t6\t6\t4.25\t4.35\t2026-08-26 04:35:19\tcompetition_qualified\trouter_isolated_xray\n' >"$UNSAFE_SWAP_COMPETITION"
build_primary_targets "$UNSAFE_SWAP_CURRENT" "$UNSAFE_SWAP_PRIMARY" "$UNSAFE_SWAP_COMPETITION" "$PRIMARY_TARGETS"
choose_pending_primary_target "$UNSAFE_SWAP_CURRENT" "$PRIMARY_TARGETS" "$PENDING"
if awk -F '\t' '$2 == "104.17.129.81" {found=1} END {exit found ? 0 : 1}' "$PENDING"; then
  echo "primary planning allowed a one-record swap that creates a duplicate" >&2
  exit 1
fi

GATE_SCRIPT="$ROOT/router-candidate-gate.sh"
WATCHLIST_FILE="$APP_DIR/router-candidate-watchlist.tsv"
CANARY_HISTORY_FILE="$APP_DIR/router-candidate-canary-history.tsv"
CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS=172800
WATCH_STAGING="$APP_DIR/candidate-staging/watchlist.tsv"
WATCH_PLAN="$TEST_TMP/watch-plan.tsv"
WATCH_QUALIFIED="$APP_DIR/watch-qualified.tsv"
STAGING_FILE="$WATCH_STAGING"
QUALIFIED_FILE="$WATCH_QUALIFIED"
TEST_EPOCH=1785859200
current_epoch() { printf '%s\n' "$TEST_EPOCH"; }
write_watch_staging() {
  local epoch="$1" first="$2" second="$3" third="$4"
  printf '%s\n' 'schema_version	exported_epoch	observed_at	candidate_ip	direct_MBps	round1_MBps	round2_MBps	min_MBps	avg_MBps	http1	http2	status	path_mode	candidate_tier' >"$WATCH_STAGING"
  for ip in "$first" "$second" "$third"; do
    printf 'cfip-sidecar-candidates-v2\t%s\t2026-08-01 03:30:00\t%s\t9.00\t4.20\t4.10\t4.10\t4.15\t200\t200\tlow\tsidecar_proxy\tobservation\n' "$epoch" "$ip" >>"$WATCH_STAGING"
  done
}
append_watch_result() {
  local observed="$1" ip="$2" epoch="$3" minimum="$4" average="$5" status="$6"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t200\t200\t20000000\t20000000\t%s\trouter_isolated_xray\n' \
    "$observed" "$ip" "$epoch" "$minimum" "$average" "$minimum" "$average" "$status" >>"$CANARY_HISTORY_FILE"
}
printf 'observed_at\tcandidate_ip\tsource_export_epoch\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tbytes1\tbytes2\tstatus\tpath_mode\n' >"$CANARY_HISTORY_FILE"

write_watch_staging "$TEST_EPOCH" 104.17.2.20 104.17.2.21 104.17.2.22
build_canary_plan "$CURRENT" "$WATCH_PLAN"
[ "$(awk 'END {print NR-1}' "$WATCH_PLAN")" -eq 3 ] || { echo "day-one canary count is not three" >&2; exit 1; }
awk -F '\t' 'NR>1 && $3!="staging"{bad=1} END{exit bad?1:0}' "$WATCH_PLAN" \
  || { echo "day-one plan did not contain only new candidates" >&2; exit 1; }
append_watch_result '2026-08-01 04:15:00' 104.17.2.20 "$TEST_EPOCH" 4.50 4.60 pass
append_watch_result '2026-08-01 04:16:00' 104.17.2.21 "$TEST_EPOCH" 4.30 4.40 pass
append_watch_result '2026-08-01 04:17:00' 104.17.2.22 "$TEST_EPOCH" 4.10 4.20 pass
refresh_watchlist "$WATCH_PLAN"
awk -F '\t' '$1=="104.17.2.20" && $2==1{a=1} $1=="104.17.2.21" && $2==1{b=1} END{exit(a&&b)?0:1}' "$WATCHLIST_FILE" \
  || { echo "day-one watchlist did not retain the best two candidates" >&2; exit 1; }
[ "$(awk 'END {print NR-1}' "$WATCHLIST_FILE")" -eq 2 ] || { echo "watchlist exceeded two entries" >&2; exit 1; }

TEST_EPOCH=$((TEST_EPOCH + 86400))
write_watch_staging "$TEST_EPOCH" 104.17.2.20 104.17.2.23 104.17.2.24
build_canary_plan "$CURRENT" "$WATCH_PLAN"
awk -F '\t' 'NR==2 && $1=="104.17.2.20" && $3=="retained"{a=1} NR==3 && $1=="104.17.2.21" && $3=="retained"{b=1} NR==4 && $1=="104.17.2.23" && $3=="staging"{c=1} END{exit(a&&b&&c)?0:1}' "$WATCH_PLAN" \
  || { echo "day-two plan is not two retained plus one new candidate" >&2; exit 1; }
[ "$(awk 'END {print NR-1}' "$WATCH_PLAN")" -eq 3 ] || { echo "day-two plan exceeded three candidates" >&2; exit 1; }
append_watch_result '2026-08-02 04:15:00' 104.17.2.20 "$TEST_EPOCH" 4.40 4.50 pass
append_watch_result '2026-08-02 04:16:00' 104.17.2.21 "$TEST_EPOCH" 4.20 4.30 pass
append_watch_result '2026-08-02 04:17:00' 104.17.2.23 "$TEST_EPOCH" 4.80 4.90 pass
refresh_watchlist "$WATCH_PLAN"
awk -F '\t' '$1=="104.17.2.20" && $2==2{a=1} $1=="104.17.2.21" && $2==2{b=1} END{exit(a&&b)?0:1}' "$WATCHLIST_FILE" \
  || { echo "streak priority did not preserve both day-two challengers" >&2; exit 1; }

TEST_EPOCH=$((TEST_EPOCH + 86400))
write_watch_staging "$TEST_EPOCH" 104.17.2.25 104.17.2.26 104.17.2.27
build_canary_plan "$CURRENT" "$WATCH_PLAN"
append_watch_result '2026-08-03 04:15:00' 104.17.2.20 "$TEST_EPOCH" 4.35 4.45 pass
append_watch_result '2026-08-03 04:16:00' 104.17.2.21 "$TEST_EPOCH" 4.15 4.25 pass
append_watch_result '2026-08-03 04:17:00' 104.17.2.25 "$TEST_EPOCH" 4.90 5.00 pass
refresh_watchlist "$WATCH_PLAN"
printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n104.17.2.20\t3\t3\t4.35\t4.52\t2026-08-03 04:15:00\tcompetition_qualified\trouter_isolated_xray\n104.17.2.21\t3\t3\t4.15\t4.32\t2026-08-03 04:16:00\tcompetition_qualified\trouter_isolated_xray\n104.17.2.99\t9\t9\t9.00\t9.00\t2026-08-03 04:17:00\tcompetition_qualified\trouter_isolated_xray\n' >"$WATCH_QUALIFIED"
choose_qualified_candidates "$TEST_TMP/watch-qualified-current.tsv" "$WATCH_PLAN"
[ "$(awk 'END {print NR}' "$TEST_TMP/watch-qualified-current.tsv")" -eq 2 ] \
  || { echo "current-cycle qualification did not return exactly two candidates" >&2; exit 1; }
if awk -F '\t' '$1=="104.17.2.99"{found=1} END{exit found?0:1}' "$TEST_TMP/watch-qualified-current.tsv"; then
  echo "orphaned old qualification entered the current DNS plan" >&2; exit 1
fi

TEST_EPOCH=$((TEST_EPOCH + 86400))
write_watch_staging "$TEST_EPOCH" 104.17.2.26 104.17.2.27 104.17.2.28
build_canary_plan "$CURRENT" "$WATCH_PLAN"
append_watch_result '2026-08-04 04:15:00' 104.17.2.20 "$TEST_EPOCH" 3.20 3.30 low
append_watch_result '2026-08-04 04:16:00' 104.17.2.21 "$TEST_EPOCH" 4.10 4.20 pass
append_watch_result '2026-08-04 04:17:00' 104.17.2.26 "$TEST_EPOCH" 4.70 4.80 pass
refresh_watchlist "$WATCH_PLAN"
if awk -F '\t' '$1=="104.17.2.20"{found=1} END{exit found?0:1}' "$WATCHLIST_FILE"; then
  echo "failed retained candidate was not evicted" >&2; exit 1
fi
awk -F '\t' '$1=="104.17.2.21"{found=1} END{exit found?0:1}' "$WATCHLIST_FILE" \
  || { echo "healthy retained candidate was lost" >&2; exit 1; }
awk -F '\t' '$1=="104.17.2.26"{found=1} END{exit found?0:1}' "$WATCHLIST_FILE" \
  || { echo "new replacement candidate was not retained" >&2; exit 1; }

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
jq() {
  local last=""
  for last in "$@"; do :; done
  grep -q '"success":true' "$last"
}
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
