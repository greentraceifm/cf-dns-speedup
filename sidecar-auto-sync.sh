#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="${CONFIG_FILE:-$APP_DIR/config.env}"
AUTO_CONFIG_FILE="${AUTO_CONFIG_FILE:-$APP_DIR/sidecar-auto-sync.env}"
GATE_SCRIPT="${CFIP_AUTO_SYNC_GATE_SCRIPT:-$APP_DIR/router-candidate-gate.sh}"
STAGING_FILE="${CFIP_CANDIDATE_STAGING_DIR:-$APP_DIR/candidate-staging}/sidecar-candidates.latest.tsv"
QUALIFIED_FILE="${CFIP_ROUTER_CANARY_QUALIFIED_FILE:-$APP_DIR/router-candidate-competition-qualified.tsv}"
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
CFIP_AUTO_SYNC_MAX_CANARIES="${CFIP_AUTO_SYNC_MAX_CANARIES:-2}"
CFIP_AUTO_SYNC_MIN_MBPS="${CFIP_AUTO_SYNC_MIN_MBPS:-6.5}"

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
  local method="$1" url="$2" output="$3" payload="${4:-}" status
  if [ -n "$payload" ]; then
    status="$(printf 'silent\nshow-error\nrequest = "%s"\nheader = "Authorization: Bearer %s"\nheader = "Content-Type: application/json"\nurl = "%s"\noutput = "%s"\nwrite-out = "%%{http_code}"\n' \
      "$method" "$CF_API_TOKEN" "$url" "$output" | curl --config - --data-binary "@$payload")"
  else
    status="$(printf 'silent\nshow-error\nrequest = "%s"\nheader = "Authorization: Bearer %s"\nurl = "%s"\noutput = "%s"\nwrite-out = "%%{http_code}"\n' \
      "$method" "$CF_API_TOKEN" "$url" "$output" | curl --config -)"
  fi
  [ "$status" = 200 ] || return 1
  jq -e '.success == true' "$output" >/dev/null
}

cf_get_record() {
  local name="$1" output="$2"
  cf_request GET "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$name" "$output"
  jq -e '.result | length == 1' "$output" >/dev/null
}

cf_patch_content() {
  local record_id="$1" content="$2" output="$3" payload="$TMP_DIR/payload.json"
  jq -n --arg content "$content" '{content: $content}' >"$payload"
  cf_request PATCH "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records/$record_id" "$output" "$payload"
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
  CFIP_AUTO_SYNC_MAX_CANARIES="${CFIP_AUTO_SYNC_MAX_CANARIES:-2}"
  CFIP_AUTO_SYNC_MIN_MBPS="${CFIP_AUTO_SYNC_MIN_MBPS:-6.5}"

  [ -n "$CF_API_TOKEN" ] || die "Cloudflare token is missing"
  [ -n "$CF_ZONE_ID" ] || die "Cloudflare zone id is missing"
  [ "$CFIP_AUTO_SYNC_APPLY" = 0 ] || [ "$CFIP_AUTO_SYNC_APPLY" = 1 ] \
    || die "CFIP_AUTO_SYNC_APPLY must be 0 or 1"
  [[ "$CFIP_AUTO_SYNC_MAX_CANARIES" =~ ^[0-9]+$ ]] \
    && [ "$CFIP_AUTO_SYNC_MAX_CANARIES" -ge 1 ] \
    && [ "$CFIP_AUTO_SYNC_MAX_CANARIES" -le 5 ] \
    || die "CFIP_AUTO_SYNC_MAX_CANARIES must be between 1 and 5"
  decimal_at_least "$CFIP_AUTO_SYNC_MIN_MBPS" 6.5 \
    || die "automatic sync threshold cannot be below 6.5 MB/s"
  [ -n "$CFIP_AUTO_SYNC_RECORDS" ] || die "automatic sync target records are missing"
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
  ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=8 \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$SSH_KNOWN_HOSTS" \
    "$REMOTE_HOST" "$REMOTE_COMMAND" >"$destination"
  [ -s "$destination" ] || die "sidecar export is empty"
  [ "$(wc -c <"$destination")" -le 65536 ] || die "sidecar export is too large"
}

run_canaries() {
  local count=0 candidate
  while IFS=$'\t' read -r _schema _epoch _observed candidate _rest; do
    [ -n "$candidate" ] || continue
    "$GATE_SCRIPT" canary "$candidate"
    count=$((count + 1))
    [ "$count" -lt "$CFIP_AUTO_SYNC_MAX_CANARIES" ] || break
  done < <(tail -n +2 "$STAGING_FILE")
}

choose_qualified_candidate() {
  local output="$1"
  [ -s "$QUALIFIED_FILE" ] || return 0
  awk -F '\t' '
    NR == FNR {if (FNR > 1) current[$4]=1; next}
    FNR > 1 && current[$1] && $7 == "competition_qualified" {print $1 "\t" $4 "\t" $5}
  ' "$STAGING_FILE" "$QUALIFIED_FILE" | sort -t $'\t' -k2,2nr -k3,3nr | head -n 1 >"$output"
}

validate_target_records() {
  local configured="${CF_RECORD_NAMES:-${CF_RECORD_NAME:-}}" target found
  [ -n "$configured" ] || die "configured Cloudflare record list is empty"
  for target in $CFIP_AUTO_SYNC_RECORDS; do
    found=0
    for record in $(printf '%s\n' "$configured" | tr ', ' '\n\n' | sed '/^$/d'); do
      [ "$target" = "$record" ] && found=1
    done
    [ "$found" -eq 1 ] || die "automatic sync target is outside configured record list: $target"
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

select_target_record() {
  local -a records=() candidates=()
  local record index=0
  for record in $CFIP_AUTO_SYNC_RECORDS; do records+=("$record"); done
  [ "${#records[@]}" -gt 0 ] || die "no automatic sync records were configured"
  if [ -r "$STATE_FILE" ]; then
    index="$(sed -n 's/^next_index=\([0-9][0-9]*\)$/\1/p' "$STATE_FILE" | tail -n 1)"
    [[ "$index" =~ ^[0-9]+$ ]] || index=0
  fi
  index=$((index % ${#records[@]}))
  printf '%s\t%s\t%s\n' "${records[$index]}" "$index" "${#records[@]}"
}

run_sync() {
  local export_file candidate_file current_records candidate candidate_min candidate_avg
  local row_count target target_index target_count current_response record_id previous_content
  local baseline_pids baseline_listeners baseline_passwall verify_response next_index

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
  candidate_file="$TMP_DIR/qualified.tsv"
  current_records="$TMP_DIR/current-records.tsv"

  pull_export "$export_file"
  "$GATE_SCRIPT" import "$export_file"
  row_count="$(awk 'NR > 1 {count++} END {print count + 0}' "$STAGING_FILE")"
  if [ "$row_count" -eq 0 ]; then
    write_report no_candidate "" "" "" sidecar_export_has_no_6.5_MBps_candidate
    log "sidecar export has no qualified candidate; Cloudflare records preserved"
    return 0
  fi

  run_canaries
  "$GATE_SCRIPT" qualify >/dev/null
  choose_qualified_candidate "$candidate_file"
  if [ ! -s "$candidate_file" ]; then
    write_report awaiting_multiday_gate "" "" "" candidate_not_yet_qualified_for_competition
    log "candidate passed export/import processing but has not completed the multi-day router gate"
    return 0
  fi

  IFS=$'\t' read -r candidate candidate_min candidate_avg <"$candidate_file"
  decimal_at_least "$candidate_min" "$CFIP_AUTO_SYNC_MIN_MBPS" \
    || die "qualified candidate is below automatic sync threshold"
  collect_current_records "$current_records"
  if awk -F '\t' -v ip="$candidate" '$2 == ip {found=1} END {exit found ? 0 : 1}' "$current_records"; then
    write_report already_present "$candidate" "" "" candidate_already_in_auto_records
    log "qualified candidate is already present in the configured records"
    return 0
  fi

  IFS=$'\t' read -r target target_index target_count < <(select_target_record)
  previous_content="$(awk -F '\t' -v name="$target" '$1 == name {print $2; exit}' "$current_records")"
  [ -n "$previous_content" ] || die "cannot determine current target record content"
  if [ "$CFIP_AUTO_SYNC_APPLY" -ne 1 ]; then
    write_report planned "$candidate" "$target" "$previous_content" apply_disabled
    log "automatic sync plan ready but apply is disabled"
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

  next_index=$(((target_index + 1) % target_count))
  printf 'next_index=%s\nlast_record=%s\nlast_candidate=%s\nupdated_at=%s\n' \
    "$next_index" "$target" "$candidate" "$(date '+%F %T')" >"$STATE_FILE.tmp.$$"
  chmod 600 "$STATE_FILE.tmp.$$"
  mv -f "$STATE_FILE.tmp.$$" "$STATE_FILE"
  write_report updated "$candidate" "$target" "$previous_content" "min=${candidate_min}_avg=${candidate_avg}"
  UPDATE_APPLIED=0
  log "Cloudflare automatic sync complete: record=$target; PassWall was not stopped or restarted"
}

status_command() {
  [ -r "$AUTO_CONFIG_FILE" ] && echo auto_config=present || echo auto_config=missing
  [ -r "$REPORT_FILE" ] && tail -n 1 "$REPORT_FILE" || echo report=missing
  (crontab -l 2>/dev/null || true) | grep -F "$APP_DIR/sidecar-auto-sync.sh" || true
}

case "${1:-run}" in
  run) run_sync ;;
  status) status_command ;;
  *) echo "Usage: $0 {run|status}" >&2; exit 2 ;;
esac
