#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="${CONFIG_FILE:-$APP_DIR/config.env}"
CFST_BIN="${CFST_BIN:-$APP_DIR/cfst}"
IP_FILE="${IP_FILE:-$APP_DIR/ip.txt}"
RESULT_FILE="${RESULT_FILE:-$APP_DIR/result.csv}"
LOG_FILE="${LOG_FILE:-$APP_DIR/run.log}"

CFST_SOURCE_BASE="${CFST_SOURCE_BASE:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3}"
DEFAULT_IP_LIST="${DEFAULT_IP_LIST:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3/ip.txt}"

log() {
  mkdir -p "$APP_DIR"
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

load_config() {
  [ -f "$CONFIG_FILE" ] || die "config not found: $CONFIG_FILE"
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"

  : "${CF_ZONE_ID:?missing CF_ZONE_ID}"
  : "${CF_API_TOKEN:?missing CF_API_TOKEN}"
  : "${CF_RECORD_NAME:?missing CF_RECORD_NAME}"

  CF_RECORD_TYPE="${CF_RECORD_TYPE:-A}"
  CF_PROXIED="${CF_PROXIED:-false}"
  CF_TTL="${CF_TTL:-60}"
  CFST_PORT="${CFST_PORT:-443}"
  CFST_THREADS="${CFST_THREADS:-32}"
  CFST_COUNT="${CFST_COUNT:-5}"
  CFST_TIMEOUT="${CFST_TIMEOUT:-4}"
  CFST_TOTAL_TIMEOUT="${CFST_TOTAL_TIMEOUT:-900}"
  CFST_DOWNLOAD_TIMEOUT="${CFST_DOWNLOAD_TIMEOUT:-8}"
  CFST_MIN_SPEED="${CFST_MIN_SPEED:-0}"
  CFST_MAX_LATENCY="${CFST_MAX_LATENCY:-9999}"
  CFST_MIN_LATENCY="${CFST_MIN_LATENCY:-0}"
  CFST_URL="${CFST_URL:-}"
  IP_VERSION="${IP_VERSION:-ipv4}"
  DRY_RUN="${DRY_RUN:-0}"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    i386|i686) echo 386 ;;
    aarch64|arm64|armv8|armv8l) echo arm64 ;;
    armv7l) echo arm ;;
    mips64le) echo mips64le ;;
    mips64) echo mips64 ;;
    mips|mipsle) echo mipsle ;;
    *) die "unsupported arch: $(uname -m)" ;;
  esac
}

install_deps_openwrt() {
  for cmd in curl jq timeout unzip; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log "missing $cmd, installing OpenWrt dependencies"
      opkg update
      opkg install curl jq coreutils-timeout unzip ca-bundle ca-certificates
      break
    fi
  done
}

download_if_missing() {
  local url="$1"
  local path="$2"
  [ -s "$path" ] && return 0
  log "download $url -> $path"
  curl -fL --connect-timeout 10 --max-time 120 --retry 2 --retry-delay 2 -o "$path" "$url"
}

prepare_assets() {
  mkdir -p "$APP_DIR"
  local arch
  arch="$(detect_arch)"
  download_if_missing "$CFST_SOURCE_BASE/$arch" "$CFST_BIN"
  chmod +x "$CFST_BIN"

  if [ "$IP_VERSION" = "ipv6" ]; then
    download_if_missing "${IPV6_LIST_URL:-$CFST_SOURCE_BASE/ipv6.txt}" "$IP_FILE"
  else
    download_if_missing "${IPV4_LIST_URL:-$DEFAULT_IP_LIST}" "$IP_FILE"
  fi
}

check_cloudflare_auth() {
  log "check Cloudflare token and zone access"
  local status
  status="$(curl -sS -o "$APP_DIR/cf-zone.json" -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID")"
  [ "$status" = "200" ] || die "Cloudflare zone API returned HTTP $status"
  jq -e '.success == true' "$APP_DIR/cf-zone.json" >/dev/null || die "Cloudflare auth failed"
}

run_speedtest() {
  rm -f "$RESULT_FILE"
  local args
  args="-tp $CFST_PORT -t $CFST_TIMEOUT -n $CFST_THREADS -dn $CFST_COUNT -p $CFST_COUNT -tl $CFST_MAX_LATENCY -tll $CFST_MIN_LATENCY -sl $CFST_MIN_SPEED -dt $CFST_DOWNLOAD_TIMEOUT -f $IP_FILE -o $RESULT_FILE"
  if [ -n "$CFST_URL" ]; then
    args="$args -url $CFST_URL"
  else
    args="$args -dd"
  fi

  log "run cfst with total timeout ${CFST_TOTAL_TIMEOUT}s"
  log "cfst output will be shown below and saved to $LOG_FILE"
  # shellcheck disable=SC2086
  if ! timeout "$CFST_TOTAL_TIMEOUT" "$CFST_BIN" $args 2>&1 | tee -a "$LOG_FILE"; then
    die "cfst failed or timed out; see $LOG_FILE"
  fi

  [ -s "$RESULT_FILE" ] || die "cfst did not create result.csv"
  local first_ip
  first_ip="$(awk -F, 'NR==2 {gsub(/[[:space:]]/, "", $1); print $1}' "$RESULT_FILE")"
  [ -n "$first_ip" ] || die "result.csv has no usable IP"
  log "best IP: $first_ip"
}

cf_api() {
  local method="$1"
  local url="$2"
  local data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS --connect-timeout 10 --max-time 30 \
      -X "$method" "$url" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$data"
  else
    curl -sS --connect-timeout 10 --max-time 30 \
      -X "$method" "$url" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json"
  fi
}

update_cloudflare() {
  local api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"
  local best_ip record_id payload response
  best_ip="$(awk -F, 'NR==2 {gsub(/[[:space:]]/, "", $1); print $1}' "$RESULT_FILE")"
  [ -n "$best_ip" ] || die "no IP to update"

  if printf '%s' "$best_ip" | grep -q ':'; then
    CF_RECORD_TYPE="AAAA"
  fi

  log "query DNS record $CF_RECORD_TYPE $CF_RECORD_NAME"
  response="$(cf_api GET "$api?type=$CF_RECORD_TYPE&name=$CF_RECORD_NAME")"
  echo "$response" > "$APP_DIR/cf-record-query.json"
  jq -e '.success == true' "$APP_DIR/cf-record-query.json" >/dev/null || die "Cloudflare DNS query failed"
  record_id="$(jq -r '.result[0].id // empty' "$APP_DIR/cf-record-query.json")"

  payload="$(jq -cn \
    --arg type "$CF_RECORD_TYPE" \
    --arg name "$CF_RECORD_NAME" \
    --arg content "$best_ip" \
    --argjson ttl "$CF_TTL" \
    --argjson proxied "$CF_PROXIED" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  if [ "$DRY_RUN" = "1" ]; then
    log "dry-run: would update $CF_RECORD_NAME -> $best_ip"
    return 0
  fi

  if [ -n "$record_id" ]; then
    log "update existing record $record_id -> $best_ip"
    response="$(cf_api PUT "$api/$record_id" "$payload")"
  else
    log "create record $CF_RECORD_NAME -> $best_ip"
    response="$(cf_api POST "$api" "$payload")"
  fi

  echo "$response" > "$APP_DIR/cf-record-update.json"
  jq -e '.success == true' "$APP_DIR/cf-record-update.json" >/dev/null || die "Cloudflare DNS update failed"
  log "Cloudflare DNS update success"
}

main() {
  load_config
  need_cmd curl
  need_cmd jq
  need_cmd timeout
  if grep -qi openwrt /etc/os-release 2>/dev/null; then
    install_deps_openwrt
  fi
  prepare_assets
  check_cloudflare_auth
  run_speedtest
  update_cloudflare
}

main "$@"
