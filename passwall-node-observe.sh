#!/usr/bin/env sh
set -eu
umask 077

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
LOCK_DIR="${CFST_PASSWALL_NODE_OBSERVE_LOCK:-/tmp/cf-dns-speedup-passwall-node-observe.lock}"
MAIN_LOCK_DIR="${LOCK_DIR_MAIN:-/tmp/cf-dns-speedup.lock}"
REPORT_FILE="${PASSWALL_NODE_REPORT_FILE:-$APP_DIR/passwall-node-benchmark.latest.tsv}"
TOPOLOGY_FILE="${PASSWALL_NODE_TOPOLOGY_FILE:-$APP_DIR/passwall-node-topology.latest.tsv}"
HISTORY_FILE="${PASSWALL_NODE_HISTORY_FILE:-$APP_DIR/passwall-node-observation-history.tsv}"
LOG_FILE="${PASSWALL_NODE_OBSERVE_LOG:-$APP_DIR/passwall-node-observe.log}"
LOG_MAX_KB="${PASSWALL_NODE_OBSERVE_LOG_MAX_KB:-1024}"

rotate_log_if_needed() {
  local size max_bytes
  case "$LOG_MAX_KB" in
    ''|*[!0-9]*|0) LOG_MAX_KB=1024 ;;
  esac
  [ -f "$LOG_FILE" ] || return 0
  size="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"
  max_bytes=$((LOG_MAX_KB * 1024))
  [ "$size" -lt "$max_bytes" ] 2>/dev/null || mv -f "$LOG_FILE" "$LOG_FILE.1"
}

mkdir -p "$APP_DIR"
rotate_log_if_needed

log() {
  mkdir -p "$APP_DIR"
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

resolve_ipv4() {
  local name="$1"
  case "$name" in
    "") return 0 ;;
    *[!0-9.]* ) ;;
    *.*.*.* ) printf '%s\n' "$name"; return 0 ;;
  esac
  command -v nslookup >/dev/null 2>&1 || return 0
  nslookup "$name" 2>/dev/null | awk '
    /^Address [0-9]+: / && $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {ip=$3}
    /^Address: / && $2 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {ip=$2}
    END {if (ip != "") print ip}
  '
}

ensure_history_file() {
  if [ ! -s "$HISTORY_FILE" ]; then
    printf 'observed_at\tsection\tremarks\taddress\tport\tbytes\ttotal_s\tspeed_bps\tspeed_MBps\thttp\tstatus\tresolved_ip\n' > "$HISTORY_FILE"
    return 0
  fi
  if ! head -n 1 "$HISTORY_FILE" | grep -q 'resolved_ip'; then
    local tmp
    tmp="$HISTORY_FILE.tmp.$$"
    awk 'NR == 1 {print $0 "\tresolved_ip"; next} {print $0 "\t"}' "$HISTORY_FILE" > "$tmp" && mv "$tmp" "$HISTORY_FILE"
  fi
}

cleanup() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  log "skip: passwall node observe already running"
  exit 0
fi

if [ -d "$MAIN_LOCK_DIR" ]; then
  log "skip: cf-dns-speedup main lock exists"
  exit 0
fi

cd "$APP_DIR"

CFST_PASSWALL_NODE_TEST_URL="${CFST_PASSWALL_NODE_TEST_URL:-https://speed.cloudflare.com/__down?bytes=5242880}" \
CFST_PASSWALL_NODE_CONNECT_TIMEOUT="${CFST_PASSWALL_NODE_CONNECT_TIMEOUT:-8}" \
CFST_PASSWALL_NODE_TIMEOUT="${CFST_PASSWALL_NODE_TIMEOUT:-35}" \
PASSWALL_NODE_REPORT_FILE="$REPORT_FILE" \
PASSWALL_NODE_TOPOLOGY_FILE="$TOPOLOGY_FILE" \
  /usr/bin/env bash ./cf-dns-speedup.sh passwall-node-check >/tmp/passwall-node-observe.out 2>/tmp/passwall-node-observe.err || {
    log "passwall-node-check failed"
    cat /tmp/passwall-node-observe.err >> "$LOG_FILE" 2>/dev/null || true
    exit 0
  }

if [ ! -s "$REPORT_FILE" ]; then
  log "skip: report missing"
  exit 0
fi

ensure_history_file

status="$(awk -F= '/^status=/ {print $2; found=1} END{if(!found) print "unknown"}' /tmp/passwall-node-observe.out)"
address="$(awk -F '\t' 'NR == 2 {print $3; exit}' "$REPORT_FILE")"
resolved_ip="$(resolve_ipv4 "$address")"
awk -F '\t' -v now="$(date '+%F %T')" -v status="$status" -v resolved_ip="$resolved_ip" 'NR == 2 {print now "\t" $0 "\t" status "\t" resolved_ip}' "$REPORT_FILE" >> "$HISTORY_FILE"
awk -F '\t' -v resolved_ip="$resolved_ip" 'NR == 2 {printf "observed global node: section=%s address=%s resolved_ip=%s speed_MBps=%s http=%s\n", $1, $3, resolved_ip, $8, $9}' "$REPORT_FILE" |
  while IFS= read -r line; do log "$line"; done
if [ -s "$TOPOLOGY_FILE" ]; then
  awk -F '\t' 'NR > 1 {printf "topology: role=%s section=%s address=%s sources=%s status=%s\n", $1, $2, $4, $6, $7}' "$TOPOLOGY_FILE" |
    while IFS= read -r line; do log "$line"; done
fi
log "passwall node observe completed: status=$status"

if [ "${CFST_PASSWALL_STABLE_REPAIR:-1}" = "1" ]; then
  /usr/bin/env bash ./cf-dns-speedup.sh passwall-stable-repair >/tmp/passwall-stable-repair.out 2>/tmp/passwall-stable-repair.err || {
    log "passwall-stable-repair failed"
    cat /tmp/passwall-stable-repair.err >> "$LOG_FILE" 2>/dev/null || true
    exit 0
  }
  awk 'NF {print "stable-repair: " $0}' /tmp/passwall-stable-repair.out >> "$LOG_FILE" 2>/dev/null || true
fi
