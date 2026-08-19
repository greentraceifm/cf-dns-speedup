#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="${CONFIG_FILE:-$APP_DIR/config.env}"
AUTO_CONFIG_FILE="${AUTO_CONFIG_FILE:-$APP_DIR/sidecar-auto-sync.env}"
GATE_SCRIPT="${CFIP_AUTO_SYNC_GATE_SCRIPT:-$APP_DIR/router-candidate-gate.sh}"
STAGING_FILE="${CFIP_CANDIDATE_STAGING_DIR:-$APP_DIR/candidate-staging}/sidecar-candidates.latest.tsv"
QUALIFIED_FILE="${CFIP_ROUTER_CANARY_QUALIFIED_FILE:-$APP_DIR/router-candidate-competition-qualified.tsv}"
CANARY_HISTORY_FILE="${CFIP_ROUTER_CANARY_HISTORY_FILE:-$APP_DIR/router-candidate-canary-history.tsv}"
WATCHLIST_FILE="${CFIP_AUTO_SYNC_WATCHLIST_FILE:-$APP_DIR/router-candidate-watchlist.tsv}"
PRIMARY_QUALIFIED_FILE="${CFIP_ROUTER_PRIMARY_CANARY_QUALIFIED_FILE:-$APP_DIR/router-primary-baseline-qualified.tsv}"
REPORT_FILE="${CFIP_AUTO_SYNC_REPORT_FILE:-$APP_DIR/sidecar-auto-sync.latest.tsv}"
HISTORY_FILE="${CFIP_AUTO_SYNC_HISTORY_FILE:-$APP_DIR/sidecar-auto-sync-history.tsv}"
STATE_FILE="${CFIP_AUTO_SYNC_STATE_FILE:-$APP_DIR/sidecar-auto-sync.state}"
LOCK_FILE="${CFIP_AUTO_SYNC_LOCK_FILE:-/tmp/cfip-sidecar-auto-sync.lock}"

REMOTE_HOST="${CFIP_AUTO_SYNC_REMOTE_HOST:-ollama@192.168.1.110}"
REMOTE_COMMAND="${CFIP_AUTO_SYNC_REMOTE_COMMAND:-read-cfip-export}"
SSH_KEY="${CFIP_AUTO_SYNC_SSH_KEY:-/root/.ssh/cfip-sidecar-export}"
SSH_KNOWN_HOSTS="${CFIP_AUTO_SYNC_KNOWN_HOSTS:-/root/.ssh/known_hosts}"

CFIP_AUTO_SYNC_APPLY="${CFIP_AUTO_SYNC_APPLY:-0}"
CFIP_AUTO_SYNC_RECORDS="${CFIP_AUTO_SYNC_RECORDS:-}"
CFIP_AUTO_SYNC_PRIMARY_RECORDS="${CFIP_AUTO_SYNC_PRIMARY_RECORDS:-}"
CFIP_AUTO_SYNC_MAX_CANARIES="${CFIP_AUTO_SYNC_MAX_CANARIES:-3}"
CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS="${CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS:-172800}"
CFIP_AUTO_SYNC_MIN_MBPS="${CFIP_AUTO_SYNC_MIN_MBPS:-3.5}"
CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS="${CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS:-4.0}"
CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT="${CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT:-25}"
CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY="${CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY:-0}"

TMP_DIR=""
UPDATE_APPLIED=0
ROLLBACK_RECORD_ID=""
ROLLBACK_RECORD_NAME=""
ROLLBACK_CONTENT=""
CF_API_TOKEN=""
CF_ZONE_ID=""

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

decimal_at_least() {
  awk -v value="$1" -v minimum="$2" 'BEGIN {exit (value + 0) >= (minimum + 0) ? 0 : 1}'
}

cf_request() {
  local method="$1" url="$2" output="$3" payload="${4:-}" status attempt=1
  while [ "$attempt" -le 3 ]; do
    rm -f "$output"
    status=""
    if [ -n "$payload" ]; then
      status="$(printf 'silent\nshow-error\nrequest = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nurl = "%s"\noutput = "%s"\nwrite-out = "%%{http_code}"\n' \
        "$method" "$CF_API_TOKEN" "$url" "$output" | curl --config - --data-binary "@$payload")" || status=""
    else
      status="$(printf 'silent\nshow-error\nrequest = "%s"\nheader = "Authorization: Bearer %s"\nurl = "%s"\noutput = "%s"\nwrite-out = "%%{http_code}"\n' \
        "$method" "$CF_API_TOKEN" "$url" "$output" | curl --config -)" || status=""
    fi
    if [ "$status" = 200 ] && jq -e '.success == true' "$output" >/dev/null 2>&1; then
      return 0
    fi
    case "$status" in
      ""|408|429|500|502|503|504) ;;
      *) return 1 ;;
    esac
    [ "$attempt" -lt 3 ] || return 1
    log "Cloudflare API request failed; retrying ($attempt/3)" >&2
    sleep 2
    attempt=$((attempt + 1))
  done
  return 1
}

cf_get_record() {
  local name="$1" output="$2"
  cf_request GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$name" "$output" || return 1
  jq -e '.result | length == 1' "$output" >/dev/null
}

cf_patch_content() {
  local record_id="$1" content="$2" output="$3" payload="$TMP_DIR/payload.json"
  jq -n --arg content "$content" '{content: $content}' >"$payload"
  cf_request PATCH "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$record_id" "$output" "$payload" || return 1
  jq -e --arg content "$content" '.result.content == $content' "$output" >/dev/null
}

cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ "$UPDATE_APPLIED" -eq 1 ] && [ -n "$ROLLBACK_RECORD_ID" ]; then
    log "failure after Cloudflare update; restoring $ROLLBACK_RECORD_NAME"
    cf_patch_content "$ROLLBACK_RECORD_ID" "$ROLLBACK_CONTENT" "$TMP_DIR/rollback.json" \
      || log "ERROR: Cloudflare rollback failed for $ROLLBACK_RECORD_NAME"
  fi
  [ -z "$TMP_DIR" ] || rm -rf "$TMP_DIR"
  exit "$rc"
}
trap cleanup EXIT INT TERM

load_config() {
  [ -r "$CONFIG_FILE" ] || die "missing config: $CONFIG_FILE"
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
  [ ! -r "$AUTO_CONFIG_FILE" ] || . "$AUTO_CONFIG_FILE"

  CF_API_TOKEN="${CF_API_TOKEN:-}"
  CF_ZONE_ID="${CF_ZONE_ID:-}"
  CFIP_AUTO_SYNC_APPLY="${CFIP_AUTO_SYNC_APPLY:-0}"
  CFIP_AUTO_SYNC_RECORDS="${CFIP_AUTO_SYNC_RECORDS:-}"
  CFIP_AUTO_SYNC_PRIMARY_RECORDS="${CFIP_AUTO_SYNC_PRIMARY_RECORDS:-}"
  CFIP_AUTO_SYNC_MAX_CANARIES="${CFIP_AUTO_SYNC_MAX_CANARIES:-3}"
  CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS="${CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS:-172800}"
  CFIP_AUTO_SYNC_MIN_MBPS="${CFIP_AUTO_SYNC_MIN_MBPS:-3.5}"
  CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS="${CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS:-4.0}"
  CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT="${CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT:-25}"
  CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY="${CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY:-0}"
  export CFIP_ROUTER_CANARY_REQUIRED_DAYS="${CFIP_ROUTER_CANARY_REQUIRED_DAYS:-3}"
  export CFIP_ROUTER_CANARY_MIN_MBPS="$CFIP_AUTO_SYNC_MIN_MBPS"
  export CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS="$CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS"

  [ -n "$CF_API_TOKEN" ] || die "Cloudflare token is missing"
  [ -n "$CF_ZONE_ID" ] || die "Cloudflare zone id is missing"
  [ "$CFIP_AUTO_SYNC_APPLY" = 0 ] || [ "$CFIP_AUTO_SYNC_APPLY" = 1 ] \
    || die "CFIP_AUTO_SYNC_APPLY must be 0 or 1"
  [[ "$CFIP_AUTO_SYNC_MAX_CANARIES" =~ ^[0-9]+$ ]] \
    && [ "$CFIP_AUTO_SYNC_MAX_CANARIES" -ge 1 ] \
    && [ "$CFIP_AUTO_SYNC_MAX_CANARIES" -le 3 ] \
    || die "CFIP_AUTO_SYNC_MAX_CANARIES must be between 1 and 3"
  [[ "$CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS" =~ ^[0-9]+$ ]] \
    && [ "$CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS" -ge 86400 ] \
    && [ "$CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS" -le 604800 ] \
    || die "watchlist max age must be between 86400 and 604800 seconds"
  decimal_at_least "$CFIP_AUTO_SYNC_MIN_MBPS" 3.5 \
    || die "automatic sync threshold cannot be below 3.5 MB/s"
  decimal_at_least "$CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS" 4.0 \
    || die "primary promotion threshold cannot be below 4.0 MB/s"
  [[ "$CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT" =~ ^[0-9]+$ ]] \
    && [ "$CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT" -ge 25 ] \
    || die "primary improvement requirement cannot be below 25 percent"
  { [ "$CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY" = 0 ] || [ "$CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY" = 1 ]; } \
    || die "CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY must be 0 or 1"
  [ -n "$CFIP_AUTO_SYNC_RECORDS" ] || die "automatic competition records are missing"
  [ -n "$CFIP_AUTO_SYNC_PRIMARY_RECORDS" ] || die "automatic primary records are missing"
}

snapshot_xray_pids() {
  pidof xray 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -n
}

snapshot_xray_listeners() {
  netstat -lntp 2>/dev/null | awk 'NR > 2 && /xray/ {print $4 "|" $7}' | sort
}

http_gate() {
  [ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://www.google.com/generate_204)" = 204 ]
  [ "$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://www.youtube.com/generate_204)" = 204 ]
}

write_report() {
  local status="$1" candidate="${2:-}" record="${3:-}" previous="${4:-}" detail="${5:-}"
  local temporary="$REPORT_FILE.tmp.$$" now
  now="$(date '+%F %T')"
  printf 'observed_at\tstatus\tcandidate_ip\trecord_name\tprevious_ip\tdetail\n' >"$temporary"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$now" "$status" "$candidate" "$record" "$previous" "$detail" >>"$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$REPORT_FILE"
  if [ ! -f "$HISTORY_FILE" ]; then
    printf 'observed_at\tstatus\tcandidate_ip\trecord_name\tprevious_ip\tdetail\n' >"$HISTORY_FILE"
    chmod 600 "$HISTORY_FILE"
  fi
  tail -n 1 "$REPORT_FILE" >>"$HISTORY_FILE"
}

pull_export() {
  local destination="$1"
  [ -f "$SSH_KEY" ] && [ ! -L "$SSH_KEY" ] || die "sidecar pull key is missing"
  [ -f "$SSH_KNOWN_HOSTS" ] || die "SSH known_hosts is missing"
  [ "$SSH_KNOWN_HOSTS" = /root/.ssh/known_hosts ] \
    || die "Dropbear requires the default SSH known_hosts path"
  timeout 15 ssh -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes \
    "$REMOTE_HOST" "$REMOTE_COMMAND" >"$destination"
  [ -s "$destination" ] || die "sidecar export is empty"
  [ "$(wc -c <"$destination")" -le 65536 ] || die "sidecar export is too large"
}

current_epoch() {
  date +%s
}

watchlist_limit() {
  local limit=$((CFIP_AUTO_SYNC_MAX_CANARIES - 1))
  [ "$limit" -le 2 ] || limit=2
  [ "$limit" -ge 0 ] || limit=0
  printf '%s\n' "$limit"
}

validate_watchlist() {
  local count=0 candidate days minimum average observed epoch status extra now
  [ -e "$WATCHLIST_FILE" ] || return 0
  [ -f "$WATCHLIST_FILE" ] && [ ! -L "$WATCHLIST_FILE" ] \
    || die "candidate watchlist must be a regular non-symlink file"
  [ "$(wc -c <"$WATCHLIST_FILE")" -le 4096 ] || die "candidate watchlist is unexpectedly large"
  [ "$(head -n 1 "$WATCHLIST_FILE")" = $'candidate_ip\tconsecutive_pass_days\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tlast_observed_epoch\tstatus' ] \
    || die "candidate watchlist header is invalid"
  now="$(current_epoch)"
  while IFS=$'\t' read -r candidate days minimum average observed epoch status extra; do
    [ -n "$candidate" ] || continue
    [ -z "${extra:-}" ] || die "candidate watchlist has extra fields"
    "$GATE_SCRIPT" validate-candidate "$candidate" >/dev/null \
      || die "candidate watchlist contains a non-Cloudflare IPv4"
    [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] || die "candidate watchlist streak is invalid"
    [[ "$minimum" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "candidate watchlist minimum is invalid"
    [[ "$average" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "candidate watchlist average is invalid"
    [[ "$epoch" =~ ^[0-9]+$ ]] && [ "$epoch" -le "$((now + 300))" ] \
      || die "candidate watchlist timestamp is invalid"
    [ "$status" = retained ] || die "candidate watchlist status is invalid"
    count=$((count + 1))
    [ "$count" -le 2 ] || die "candidate watchlist contains more than two entries"
  done < <(tail -n +2 "$WATCHLIST_FILE")
}

build_canary_plan() {
  local current_records="$1" output="$2" source_epoch retained_limit now count=0
  local candidate days minimum average observed epoch status extra primary1 primary2 primary3
  local -a primary_names=()
  local seen=""
  read -r -a primary_names <<<"$CFIP_AUTO_SYNC_PRIMARY_RECORDS"
  [ "${#primary_names[@]}" -eq 3 ] || die "exactly three primary records are required"
  primary1="$(record_content "$current_records" "${primary_names[0]}")"
  primary2="$(record_content "$current_records" "${primary_names[1]}")"
  primary3="$(record_content "$current_records" "${primary_names[2]}")"
  [ -n "$primary1" ] && [ -n "$primary2" ] && [ -n "$primary3" ] \
    || die "cannot resolve all primary record contents"
  source_epoch="$(awk -F '\t' 'NR == 2 {print $2; exit}' "$STAGING_FILE")"
  printf 'candidate_ip\tsource_export_epoch\tsource\n' >"$output"
  [ -n "$source_epoch" ] || return 0
  retained_limit="$(watchlist_limit)"
  now="$(current_epoch)"
  validate_watchlist
  if [ "$retained_limit" -gt 0 ] && [ -s "$WATCHLIST_FILE" ]; then
    while IFS=$'\t' read -r candidate days minimum average observed epoch status extra; do
      [ -n "$candidate" ] || continue
      [ "$((now - epoch))" -le "$CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS" ] || continue
      case "$candidate" in "$primary1"|"$primary2"|"$primary3") continue ;; esac
      case " $seen " in *" $candidate "*) continue ;; esac
      printf '%s\t%s\tretained\n' "$candidate" "$source_epoch" >>"$output"
      seen="$seen $candidate"
      count=$((count + 1))
      [ "$count" -lt "$retained_limit" ] || break
    done < <(tail -n +2 "$WATCHLIST_FILE")
  fi
  while IFS=$'\t' read -r _schema epoch _observed candidate _rest; do
    [ -n "$candidate" ] || continue
    case "$candidate" in "$primary1"|"$primary2"|"$primary3") continue ;; esac
    case " $seen " in *" $candidate "*) continue ;; esac
    printf '%s\t%s\tstaging\n' "$candidate" "$epoch" >>"$output"
    seen="$seen $candidate"
    count=$((count + 1))
    [ "$count" -lt "$CFIP_AUTO_SYNC_MAX_CANARIES" ] || break
  done < <(tail -n +2 "$STAGING_FILE")
}

run_canaries() {
  local plan="$1" count=0 candidate _epoch _source
  while IFS=$'\t' read -r candidate _epoch _source; do
    [ -n "$candidate" ] || continue
    CFIP_ROUTER_CANARY_ALLOWED_FILE="$plan" "$GATE_SCRIPT" canary "$candidate"
    count=$((count + 1))
    [ "$count" -lt "$CFIP_AUTO_SYNC_MAX_CANARIES" ] || break
  done < <(tail -n +2 "$plan")
}

refresh_watchlist() {
  local plan="$1" temporary="$WATCHLIST_FILE.tmp.$$" rows="$WATCHLIST_FILE.rows.$$"
  local candidate source_epoch source result observed minimum average status
  local previous days previous_min previous_avg previous_observed previous_epoch previous_status
  local now current_date previous_date retained_limit
  retained_limit="$(watchlist_limit)"
  mkdir -p "$(dirname "$WATCHLIST_FILE")"
  : >"$rows"
  now="$(current_epoch)"
  while IFS=$'\t' read -r candidate source_epoch source; do
    [ -n "$candidate" ] || continue
    result="$(awk -F '\t' -v ip="$candidate" -v epoch="$source_epoch" \
      '$2 == ip && $3 == epoch {row=$0} END {print row}' "$CANARY_HISTORY_FILE")"
    [ -n "$result" ] || die "candidate canary result is missing from history"
    IFS=$'\t' read -r observed _candidate _source_epoch _round1 _round2 minimum average \
      _http1 _http2 _bytes1 _bytes2 status _path <<<"$result"
    [ "$status" = pass ] || continue
    previous=""
    if [ -s "$WATCHLIST_FILE" ]; then
      previous="$(awk -F '\t' -v ip="$candidate" 'NR > 1 && $1 == ip {print; exit}' "$WATCHLIST_FILE")"
    fi
    days=1
    if [ -n "$previous" ]; then
      IFS=$'\t' read -r _candidate days previous_min previous_avg previous_observed previous_epoch previous_status <<<"$previous"
      current_date="${observed%% *}"
      previous_date="${previous_observed%% *}"
      if [ "$current_date" = "$previous_date" ]; then
        minimum="$(awk -v a="$previous_min" -v b="$minimum" 'BEGIN {printf "%.2f", a < b ? a : b}')"
      elif [ "$((now - previous_epoch))" -le "$CFIP_AUTO_SYNC_WATCHLIST_MAX_AGE_SECONDS" ]; then
        days=$((days + 1))
        minimum="$(awk -v a="$previous_min" -v b="$minimum" 'BEGIN {printf "%.2f", a < b ? a : b}')"
        average="$(awk -v old="$previous_avg" -v current="$average" -v days="$days" \
          'BEGIN {printf "%.2f", ((old * (days - 1)) + current) / days}')"
      else
        days=1
      fi
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\tretained\n' \
      "$candidate" "$days" "$minimum" "$average" "$observed" "$now" >>"$rows"
  done < <(tail -n +2 "$plan")
  printf 'candidate_ip\tconsecutive_pass_days\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tlast_observed_epoch\tstatus\n' >"$temporary"
  if [ "$retained_limit" -gt 0 ]; then
    rank_watchlist_rows "$retained_limit" <"$rows" >>"$temporary"
  fi
  chmod 600 "$temporary"
  mv -f "$temporary" "$WATCHLIST_FILE"
  rm -f "$rows"
}

run_primary_canaries() {
  local current_records="$1" name candidate seen=""
  local -a primary_names=()
  read -r -a primary_names <<<"$CFIP_AUTO_SYNC_PRIMARY_RECORDS"
  [ "${#primary_names[@]}" -eq 3 ] || die "exactly three primary records are required"
  for name in "${primary_names[@]}"; do
    candidate="$(record_content "$current_records" "$name")"
    [ -n "$candidate" ] || die "cannot determine current primary record content"
    case " $seen " in *" $candidate "*) continue ;; esac
    "$GATE_SCRIPT" primary-canary "$candidate"
    seen="$seen $candidate"
  done
}
choose_qualified_candidates() {
  local output="$1" plan="${2:-$STAGING_FILE}"
  [ -s "$QUALIFIED_FILE" ] || { : >"$output"; return 0; }
  awk -F '\t' '
    NR == FNR {
      if (FNR == 1) {candidate_column=($1 == "candidate_ip" ? 1 : 4); next}
      current[$candidate_column]=1
      next
    }
    FNR > 1 && current[$1] && $7 == "competition_qualified" {
      print $1 "\t" $2 "\t" $4 "\t" $5
    }
  ' "$plan" "$QUALIFIED_FILE" \
    | rank_candidate_rows 2 >"$output"
}

rank_watchlist_rows() {
  local limit="$1"
  awk -F '\t' -v limit="$limit" '
    function better(a, b) {
      if (days[a] != days[b]) return days[a] > days[b]
      if (minimum[a] != minimum[b]) return minimum[a] > minimum[b]
      if (average[a] != average[b]) return average[a] > average[b]
      return candidate[a] < candidate[b]
    }
    function swap(a, b, value) {
      value=row[a]; row[a]=row[b]; row[b]=value
      value=candidate[a]; candidate[a]=candidate[b]; candidate[b]=value
      value=days[a]; days[a]=days[b]; days[b]=value
      value=minimum[a]; minimum[a]=minimum[b]; minimum[b]=value
      value=average[a]; average[a]=average[b]; average[b]=value
    }
    NF >= 4 {
      count++
      row[count]=$0
      candidate[count]=$1
      days[count]=$2+0
      minimum[count]=$3+0
      average[count]=$4+0
    }
    END {
      for (i=1; i<=count; i++) {
        best=i
        for (j=i+1; j<=count; j++) if (better(j, best)) best=j
        if (best != i) swap(i, best)
      }
      for (i=1; i<=count && i<=limit; i++) print row[i]
    }
  '
}

rank_candidate_rows() {
  local limit="$1"
  awk -F '\t' -v limit="$limit" '
    function better(a, b) {
      if (minimum[a] != minimum[b]) return minimum[a] > minimum[b]
      if (average[a] != average[b]) return average[a] > average[b]
      if (days[a] != days[b]) return days[a] > days[b]
      return candidate[a] < candidate[b]
    }
    function swap(a, b, value) {
      value=row[a]; row[a]=row[b]; row[b]=value
      value=candidate[a]; candidate[a]=candidate[b]; candidate[b]=value
      value=days[a]; days[a]=days[b]; days[b]=value
      value=minimum[a]; minimum[a]=minimum[b]; minimum[b]=value
      value=average[a]; average[a]=average[b]; average[b]=value
    }
    NF >= 4 {
      count++
      row[count]=$0
      candidate[count]=$1
      days[count]=$2+0
      minimum[count]=$3+0
      average[count]=$4+0
    }
    END {
      for (i=1; i<=count; i++) {
        best=i
        for (j=i+1; j<=count; j++) if (better(j, best)) best=j
        if (best != i) swap(i, best)
      }
      for (i=1; i<=count && i<=limit; i++) print row[i]
    }
  '
}

record_content() {
  local records_file="$1" name="$2"
  awk -F '\t' -v name="$name" '$1 == name {print $2; exit}' "$records_file"
}

build_competition_targets() {
  local current_records="$1" qualified="$2" output="$3"
  local -a competition_names=() primary_names=() challengers=() mins=() avgs=()
  local name ip days minimum average primary_ip desired source index
  read -r -a competition_names <<<"$CFIP_AUTO_SYNC_RECORDS"
  read -r -a primary_names <<<"$CFIP_AUTO_SYNC_PRIMARY_RECORDS"
  [ "${#competition_names[@]}" -eq 2 ] || die "exactly two competition records are required"
  [ "${#primary_names[@]}" -eq 3 ] || die "exactly three primary records are required"
  local primary1 primary2 primary3
  primary1="$(record_content "$current_records" "${primary_names[0]}")"
  primary2="$(record_content "$current_records" "${primary_names[1]}")"
  primary3="$(record_content "$current_records" "${primary_names[2]}")"
  [ -n "$primary1" ] && [ -n "$primary2" ] && [ -n "$primary3" ] \
    || die "cannot resolve all primary record contents"

  while IFS=$'\t' read -r ip days minimum average; do
    [ -n "$ip" ] || continue
    case "$ip" in "$primary1"|"$primary2"|"$primary3") continue ;; esac
    challengers+=("$ip"); mins+=("$minimum"); avgs+=("$average")
    [ "${#challengers[@]}" -ge 2 ] && break
  done <"$qualified"

  : >"$output"
  for index in 0 1; do
    name="${competition_names[$index]}"
    if [ "$index" -lt "${#challengers[@]}" ]; then
      desired="${challengers[$index]}"; minimum="${mins[$index]}"; average="${avgs[$index]}"; source=challenger
    elif [ "$index" -eq 0 ]; then
      desired="$primary1"; minimum=""; average=""; source=stable_mirror
    else
      desired="$primary2"; minimum=""; average=""; source=stable_mirror
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$desired" "$minimum" "$average" "$source" >>"$output"
  done
}

PRIMARY_BASELINE_READY=0

build_primary_targets() {
  local current_records="$1" primary_qualified="$2" competition_qualified="$3" output="$4"
  local pool="$output.pool.$$" ranked="$output.ranked.$$" rc=0 index=0 name
  local -a primary_names=() winners=() mins=() avgs=() sources=()
  read -r -a primary_names <<<"$CFIP_AUTO_SYNC_PRIMARY_RECORDS"
  [ "${#primary_names[@]}" -eq 3 ] || die "exactly three primary records are required"
  : >"$output"
  PRIMARY_BASELINE_READY=0

  awk -F '\t' -v current_file="$current_records" -v primary_file="$primary_qualified" \
      -v competition_file="$competition_qualified" -v primary_names="$CFIP_AUTO_SYNC_PRIMARY_RECORDS" \
      -v competition_names="$CFIP_AUTO_SYNC_RECORDS" -v primary_min="$CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS" \
      -v improvement="$CFIP_AUTO_SYNC_PRIMARY_IMPROVEMENT_PERCENT" '
    FILENAME == current_file {records[$1]=$2; next}
    FILENAME == primary_file {
      if (FNR > 1 && $7 == "primary_baseline_qualified") {
        p_days[$1]=$2+0; p_min[$1]=$4+0; p_avg[$1]=$5+0
      }
      next
    }
    FILENAME == competition_file {
      if (FNR > 1 && $7 == "competition_qualified") {
        c_days[$1]=$2+0; c_min[$1]=$4+0; c_avg[$1]=$5+0
      }
      next
    }
    END {
      primary_count=split(primary_names, primary_record, /[ ]+/)
      competition_count=split(competition_names, competition_record, /[ ]+/)
      weak_min=""
      for (i=1; i<=primary_count; i++) {
        ip=records[primary_record[i]]
        if (ip == "") exit 4
        if (ip in current_primary) duplicate_primary=1
        current_primary[ip]=1
        if (ip in p_min) {
          pool[ip]=1; days[ip]=p_days[ip]; minimum[ip]=p_min[ip]; average[ip]=p_avg[ip]; source[ip]="primary_history"
        } else if ((ip in c_min) && c_min[ip] >= primary_min) {
          pool[ip]=1; days[ip]=c_days[ip]; minimum[ip]=c_min[ip]; average[ip]=c_avg[ip]; source[ip]="competition_history"
        } else exit 3
        if (weak_min == "" || minimum[ip] < weak_min) weak_min=minimum[ip]
      }
      for (ip in p_min) {
        pool[ip]=1; days[ip]=p_days[ip]; minimum[ip]=p_min[ip]; average[ip]=p_avg[ip]; source[ip]="primary_history"
      }
      for (i=1; i<=competition_count; i++) {
        ip=records[competition_record[i]]
        if (ip == "" || (ip in current_primary) || !(ip in c_min)) continue
        if (c_min[ip] < primary_min) continue
        if (duplicate_primary) {
          if (c_min[ip] <= weak_min) continue
          pool[ip]=1; days[ip]=c_days[ip]; minimum[ip]=c_min[ip]; average[ip]=c_avg[ip]; source[ip]="duplicate_repair"
        } else {
          if ((c_min[ip] * 100) + 0.0001 < weak_min * (100 + improvement)) continue
          pool[ip]=1; days[ip]=c_days[ip]; minimum[ip]=c_min[ip]; average[ip]=c_avg[ip]; source[ip]="challenger"
        }
      }
      for (ip in pool)
        printf "%s\t%d\t%.2f\t%.2f\t%s\n", ip, days[ip], minimum[ip], average[ip], source[ip]
    }
  ' "$current_records" "$primary_qualified" "$competition_qualified" >"$pool" || rc=$?
  case "$rc" in
    0) ;;
    3) rm -f "$pool" "$ranked"; return 0 ;;
    4) rm -f "$pool" "$ranked"; die "cannot resolve all primary record contents" ;;
    *) rm -f "$pool" "$ranked"; die "cannot build primary ranking pool" ;;
  esac

  rank_candidate_rows 3 <"$pool" >"$ranked"
  [ "$(awk 'END {print NR + 0}' "$ranked")" -eq 3 ] \
    || { rm -f "$pool" "$ranked"; return 0; }
  while IFS=$'\t' read -r candidate days minimum average source; do
    winners+=("$candidate"); mins+=("$minimum"); avgs+=("$average"); sources+=("$source")
  done <"$ranked"
  local duplicate_primary=0 seen_current="" current_candidate row
  for name in "${primary_names[@]}"; do
    current_candidate="$(record_content "$current_records" "$name")"
    case " $seen_current " in
      *" $current_candidate "*) duplicate_primary=1 ;;
      *) seen_current="$seen_current $current_candidate" ;;
    esac
  done
  if [ "$duplicate_primary" -eq 1 ]; then
    local assigned="" selected_candidate selected_days selected_min selected_avg selected_source
    : >"$output"
    for name in "${primary_names[@]}"; do
      current_candidate="$(record_content "$current_records" "$name")"
      case " $assigned " in
        *" $current_candidate "*)
          selected_candidate=""; selected_days=""; selected_min=""; selected_avg=""; selected_source=""
          while IFS=$'\t' read -r candidate days minimum average source; do
            case " $assigned " in *" $candidate "*) continue ;; esac
            selected_candidate="$candidate"; selected_days="$days"; selected_min="$minimum"
            selected_avg="$average"; selected_source="$source"; break
          done <"$ranked"
          [ -n "$selected_candidate" ] || { rm -f "$pool" "$ranked"; return 0; }
          printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$selected_candidate" "$selected_min" \
            "$selected_avg" "$selected_source" >>"$output"
          assigned="$assigned $selected_candidate"
          ;;
        *)
          row="$(awk -F '\t' -v ip="$current_candidate" '$1 == ip {print; exit}' "$ranked")"
          [ -n "$row" ] || { rm -f "$pool" "$ranked"; return 0; }
          IFS=$'\t' read -r selected_candidate selected_days selected_min selected_avg selected_source <<<"$row"
          printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$selected_candidate" "$selected_min" \
            "$selected_avg" "$selected_source" >>"$output"
          assigned="$assigned $selected_candidate"
          ;;
      esac
    done
    PRIMARY_BASELINE_READY=1
    rm -f "$pool" "$ranked"
    return 0
  fi
  for index in 0 1 2; do
    name="${primary_names[$index]}"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${winners[$index]}" "${mins[$index]}" \
      "${avgs[$index]}" "${sources[$index]}" >>"$output"
  done
  rm -f "$pool" "$ranked"
  PRIMARY_BASELINE_READY=1
}
choose_pending_target() {
  local current_records="$1" targets="$2" output="$3"
  local name desired minimum average source current
  : >"$output"
  while IFS=$'\t' read -r name desired minimum average source; do
    current="$(record_content "$current_records" "$name")"
    [ -n "$current" ] || die "cannot determine current target record content"
    if [ "$current" != "$desired" ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$name" "$desired" "$current" "$minimum" "$average" "$source" >"$output"
      return 0
    fi
  done <"$targets"
}
validate_target_records() {
  local configured="${CF_RECORD_NAMES:-${CF_RECORD_NAME:-}}" target found
  local -a competition=() primary=()
  [ -n "$configured" ] || die "configured Cloudflare record list is empty"
  read -r -a competition <<<"$CFIP_AUTO_SYNC_RECORDS"
  read -r -a primary <<<"$CFIP_AUTO_SYNC_PRIMARY_RECORDS"
  [ "${#competition[@]}" -eq 2 ] || die "exactly two competition records must be configured"
  [ "${#primary[@]}" -eq 3 ] || die "exactly three primary records must be configured"
  for target in "${primary[@]}" "${competition[@]}"; do
    found=0
    for record in $(printf '%s\n' "$configured" | tr ', ' '\n\n' | sed '/^$/d'); do
      [ "$target" = "$record" ] && found=1
    done
    [ "$found" -eq 1 ] || die "automatic sync target is outside configured record list: $target"
  done
  for target in "${primary[@]}"; do
    case " $CFIP_AUTO_SYNC_RECORDS " in *" $target "*) die "primary and competition records must be disjoint" ;; esac
  done
}
collect_current_records() {
  local output="$1" configured="${CF_RECORD_NAMES:-${CF_RECORD_NAME:-}}" record response
  : >"$output"
  for record in $(printf '%s\n' "$configured" | tr ', ' '\n\n' | sed '/^$/d'); do
    response="$TMP_DIR/record-$(printf '%s' "$record" | sha256sum | awk '{print $1}').json"
    cf_get_record "$record" "$response" || die "cannot read Cloudflare record: $record"
    printf '%s\t%s\n' "$record" "$(jq -r '.result[0].content' "$response")" >>"$output"
  done
}

run_sync() {
  local export_file qualified_file current_records competition_targets primary_targets pending row_count canary_plan
  local target candidate previous_content candidate_min candidate_avg target_source target_kind=""
  local current_response record_id baseline_pids baseline_listeners baseline_passwall verify_response apply_enabled

  load_config
  for command in awk bash curl flock jq netstat pidof sha256sum ssh timeout; do need_cmd "$command"; done
  [ -x "$GATE_SCRIPT" ] || die "router candidate gate is not executable"
  validate_target_records
  mkdir -p "$APP_DIR"
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "another sidecar auto sync is running"
  [ ! -e /tmp/cf-dns-speedup.lock ] || die "main CFIP project lock is present"

  baseline_pids="$(snapshot_xray_pids)"
  baseline_listeners="$(snapshot_xray_listeners)"
  baseline_passwall="$(sha256sum /etc/config/passwall | awk '{print $1}')"
  [ -n "$baseline_pids" ] || die "no active PassWall Xray process"
  [ -n "$baseline_listeners" ] || die "no active PassWall Xray listener"
  http_gate || die "HTTP gate failed before sidecar sync"

  TMP_DIR="$(mktemp -d /tmp/cfip-sidecar-auto-sync.XXXXXX)"
  chmod 700 "$TMP_DIR"
  export_file="$TMP_DIR/candidates.tsv"
  qualified_file="$TMP_DIR/qualified.tsv"
  current_records="$TMP_DIR/current-records.tsv"
  competition_targets="$TMP_DIR/competition-targets.tsv"
  primary_targets="$TMP_DIR/primary-targets.tsv"
  pending="$TMP_DIR/pending-target.tsv"
  canary_plan="$TMP_DIR/canary-plan.tsv"

  pull_export "$export_file"
  "$GATE_SCRIPT" import "$export_file"
  row_count="$(awk 'NR > 1 {count++} END {print count + 0}' "$STAGING_FILE")"
  collect_current_records "$current_records"
  : >"$qualified_file"
  if [ "$row_count" -gt 0 ]; then
    build_canary_plan "$current_records" "$canary_plan"
    run_canaries "$canary_plan"
    "$GATE_SCRIPT" qualify >/dev/null
    refresh_watchlist "$canary_plan"
    choose_qualified_candidates "$qualified_file" "$canary_plan"
  fi
  run_primary_canaries "$current_records"
  "$GATE_SCRIPT" primary-qualify >/dev/null

  build_competition_targets "$current_records" "$qualified_file" "$competition_targets"
  choose_pending_target "$current_records" "$competition_targets" "$pending"
  if [ -s "$pending" ]; then
    target_kind=competition
  else
    build_primary_targets "$current_records" "$PRIMARY_QUALIFIED_FILE" "$QUALIFIED_FILE" "$primary_targets"
    if [ "$PRIMARY_BASELINE_READY" -eq 1 ]; then
      choose_pending_target "$current_records" "$primary_targets" "$pending"
      [ ! -s "$pending" ] || target_kind=primary
    fi
  fi

  if [ ! -s "$pending" ]; then
    if [ "$PRIMARY_BASELINE_READY" -ne 1 ]; then
      write_report awaiting_primary_baseline "" "" "" primary_records_need_three_distinct_days_on_router_isolated_xray
      log "primary records have not completed the consecutive three-day same-path baseline"
    elif [ "$row_count" -eq 0 ]; then
      write_report no_candidate "" "" "" sidecar_export_has_no_3.5_MBps_observation_candidate
      log "sidecar export has no observation candidate; primary and competition slots are already safe"
    elif [ ! -s "$qualified_file" ]; then
      write_report awaiting_multiday_gate "" "" "" candidate_not_yet_qualified_for_competition
      log "observation candidates have not completed the consecutive three-day router gate"
    else
      candidate="$(awk -F '\t' 'NR == 1 {print $1}' "$qualified_file")"
      write_report already_present "$candidate" "" "" competition_and_primary_slots_already_match_ranked_targets
      log "competition and primary slots already match the ranked targets"
    fi
    return 0
  fi

  IFS=$'\t' read -r target candidate previous_content candidate_min candidate_avg target_source <"$pending"
  if [ "$target_kind" = competition ] && [ "$target_source" = challenger ]; then
    decimal_at_least "$candidate_min" "$CFIP_AUTO_SYNC_MIN_MBPS" \
      || die "qualified challenger is below automatic sync threshold"
  fi
  if [ "$target_kind" = primary ]; then
    decimal_at_least "$candidate_min" "$CFIP_AUTO_SYNC_PRIMARY_MIN_MBPS" \
      || die "primary target is below the automatic primary threshold"
    apply_enabled="$CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY"
  else
    apply_enabled="$CFIP_AUTO_SYNC_APPLY"
  fi
  if [ "$apply_enabled" -ne 1 ]; then
    if [ "$target_kind" = primary ]; then
      write_report primary_planned "$candidate" "$target" "$previous_content" "source=$target_source"
      log "primary slot plan ready but primary promotion apply is disabled"
    else
      write_report planned "$candidate" "$target" "$previous_content" "source=$target_source"
      log "competition slot plan ready but apply is disabled"
    fi
    return 0
  fi

  current_response="$TMP_DIR/target-current.json"
  cf_get_record "$target" "$current_response" || die "cannot refresh target record before update"
  record_id="$(jq -r '.result[0].id' "$current_response")"
  [ -n "$record_id" ] && [ "$record_id" != null ] || die "target record id is missing"
  [ "$(jq -r '.result[0].content' "$current_response")" = "$previous_content" ] \
    || die "target record changed concurrently"

  ROLLBACK_RECORD_ID="$record_id"
  ROLLBACK_RECORD_NAME="$target"
  ROLLBACK_CONTENT="$previous_content"
  cf_patch_content "$record_id" "$candidate" "$TMP_DIR/update.json" \
    || die "Cloudflare record update failed"
  UPDATE_APPLIED=1
  verify_response="$TMP_DIR/verify.json"
  cf_get_record "$target" "$verify_response" || die "Cloudflare verification GET failed"
  [ "$(jq -r '.result[0].content' "$verify_response")" = "$candidate" ] \
    || die "Cloudflare verification content mismatch"

  [ "$(snapshot_xray_pids)" = "$baseline_pids" ] || die "PassWall Xray PID changed"
  [ "$(snapshot_xray_listeners)" = "$baseline_listeners" ] || die "PassWall Xray listeners changed"
  [ "$(sha256sum /etc/config/passwall | awk '{print $1}')" = "$baseline_passwall" ] \
    || die "PassWall configuration changed"
  http_gate || die "HTTP gate failed after Cloudflare update"

  printf 'last_record=%s\nlast_candidate=%s\nlast_source=%s\nupdated_at=%s\n' \
    "$target" "$candidate" "$target_source" "$(date '+%F %T')" >"$STATE_FILE.tmp.$$"
  chmod 600 "$STATE_FILE.tmp.$$"
  mv -f "$STATE_FILE.tmp.$$" "$STATE_FILE"
  if [ "$target_kind" = primary ]; then
    write_report primary_updated "$candidate" "$target" "$previous_content" \
      "source=${target_source}_min=${candidate_min:-n/a}_avg=${candidate_avg:-n/a}"
  else
    write_report updated "$candidate" "$target" "$previous_content" \
      "source=${target_source}_min=${candidate_min:-n/a}_avg=${candidate_avg:-n/a}"
  fi
  UPDATE_APPLIED=0
  log "Cloudflare $target_kind slot sync complete: record=$target; PassWall was not stopped or restarted"
}
status_command() {
  [ -r "$AUTO_CONFIG_FILE" ] && echo auto_config=present || echo auto_config=missing
  [ -r "$REPORT_FILE" ] && tail -n 1 "$REPORT_FILE" || echo report=missing
  (crontab -l 2>/dev/null || true) | grep -F "$APP_DIR/sidecar-auto-sync.sh" || true
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-run}" in
    run) run_sync ;;
    status) status_command ;;
    *) echo "Usage: $0 {run|status}" >&2; exit 2 ;;
  esac
fi
