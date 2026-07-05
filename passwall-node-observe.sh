#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
LOCK_DIR="${CFST_PASSWALL_NODE_OBSERVE_LOCK:-/tmp/cf-dns-speedup-passwall-node-observe.lock}"
MAIN_LOCK_DIR="${LOCK_DIR_MAIN:-/tmp/cf-dns-speedup.lock}"
REPORT_FILE="${PASSWALL_NODE_REPORT_FILE:-$APP_DIR/passwall-node-benchmark.latest.tsv}"
HISTORY_FILE="${PASSWALL_NODE_HISTORY_FILE:-$APP_DIR/passwall-node-observation-history.tsv}"
LOG_FILE="${PASSWALL_NODE_OBSERVE_LOG:-$APP_DIR/passwall-node-observe.log}"

log() {
  mkdir -p "$APP_DIR"
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
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
  /usr/bin/env bash ./cf-dns-speedup.sh passwall-node-check >/tmp/passwall-node-observe.out 2>/tmp/passwall-node-observe.err || {
    log "passwall-node-check failed"
    cat /tmp/passwall-node-observe.err >> "$LOG_FILE" 2>/dev/null || true
    exit 0
  }

if [ ! -s "$REPORT_FILE" ]; then
  log "skip: report missing"
  exit 0
fi

if [ ! -s "$HISTORY_FILE" ]; then
  printf 'observed_at\tsection\tremarks\taddress\tport\tbytes\ttotal_s\tspeed_bps\tspeed_MBps\thttp\tstatus\n' > "$HISTORY_FILE"
fi

status="$(awk -F= '/^status=/ {print $2; found=1} END{if(!found) print "unknown"}' /tmp/passwall-node-observe.out)"
awk -F '\t' -v now="$(date '+%F %T')" -v status="$status" 'NR == 2 {print now "\t" $0 "\t" status}' "$REPORT_FILE" >> "$HISTORY_FILE"
log "passwall node observe completed: status=$status"
