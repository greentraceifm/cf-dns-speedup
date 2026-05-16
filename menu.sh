#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="$APP_DIR/config.env"
RUNNER="$APP_DIR/cf-dns-speedup.sh"
LOG_FILE="$APP_DIR/run.log"

ensure_config() {
  mkdir -p "$APP_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cp "$APP_DIR/config.example.env" "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
  fi
}

get_value() {
  key="$1"
  grep -E "^${key}=" "$CONFIG_FILE" 2>/dev/null | tail -n 1 | sed "s/^${key}=//; s/^\"//; s/\"$//"
}

set_value() {
  key="$1"
  value="$2"
  escaped=$(printf '%s' "$value" | sed 's/[\/&]/\\&/g')
  if grep -qE "^${key}=" "$CONFIG_FILE"; then
    sed -i "s/^${key}=.*/${key}=\"${escaped}\"/" "$CONFIG_FILE"
  else
    printf '%s="%s"\n' "$key" "$value" >> "$CONFIG_FILE"
  fi
}

set_bool_or_number() {
  key="$1"
  value="$2"
  if grep -qE "^${key}=" "$CONFIG_FILE"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$CONFIG_FILE"
  fi
}

pause() {
  printf '\nPress Enter to continue...'
  read -r _
}

show_config() {
  ensure_config
  echo
  echo "Current config:"
  echo "  CF_ZONE_ID=$(get_value CF_ZONE_ID)"
  echo "  CF_RECORD_NAME=$(get_value CF_RECORD_NAME)"
  echo "  CF_RECORD_TYPE=$(get_value CF_RECORD_TYPE)"
  echo "  CF_PROXIED=$(get_value CF_PROXIED)"
  echo "  CF_TTL=$(get_value CF_TTL)"
  echo "  CFST_PORT=$(get_value CFST_PORT)"
  echo "  CFST_THREADS=$(get_value CFST_THREADS)"
  echo "  CFST_COUNT=$(get_value CFST_COUNT)"
  echo "  CFST_TOTAL_TIMEOUT=$(get_value CFST_TOTAL_TIMEOUT)"
  echo "  CFST_URL=$(get_value CFST_URL)"
  echo "  IP_VERSION=$(get_value IP_VERSION)"
  echo "  DRY_RUN=$(get_value DRY_RUN)"
  echo "  CF_API_TOKEN=$(mask_token "$(get_value CF_API_TOKEN)")"
}

mask_token() {
  token="$1"
  [ -n "$token" ] || { echo ""; return; }
  case "$token" in
    put_your*) echo "$token" ;;
    *) echo "********" ;;
  esac
}

setup_cloudflare() {
  ensure_config
  echo
  printf "Cloudflare API Token: "
  read -r token
  [ -n "$token" ] && set_value CF_API_TOKEN "$token"
  printf "Cloudflare Zone ID: "
  read -r zone
  [ -n "$zone" ] && set_value CF_ZONE_ID "$zone"
  printf "DNS record full name, example best.example.com: "
  read -r record
  [ -n "$record" ] && set_value CF_RECORD_NAME "$record"
  printf "Record type [A]: "
  read -r record_type
  [ -n "$record_type" ] || record_type="A"
  set_value CF_RECORD_TYPE "$record_type"
  printf "Proxied through Cloudflare? true/false [false]: "
  read -r proxied
  [ -n "$proxied" ] || proxied="false"
  set_bool_or_number CF_PROXIED "$proxied"
  echo "Saved Cloudflare settings."
}

setup_speedtest() {
  ensure_config
  echo
  printf "Port [443]: "
  read -r port
  [ -n "$port" ] || port="443"
  set_bool_or_number CFST_PORT "$port"
  printf "Threads [32, router-safe recommended 16-32]: "
  read -r threads
  [ -n "$threads" ] || threads="32"
  set_bool_or_number CFST_THREADS "$threads"
  printf "Result count [5]: "
  read -r count
  [ -n "$count" ] || count="5"
  set_bool_or_number CFST_COUNT "$count"
  printf "Total timeout seconds [900]: "
  read -r total_timeout
  [ -n "$total_timeout" ] || total_timeout="900"
  set_bool_or_number CFST_TOTAL_TIMEOUT "$total_timeout"
  printf "Download speed URL, empty means latency-only: "
  read -r url
  set_value CFST_URL "$url"
  printf "IP version ipv4/ipv6 [ipv4]: "
  read -r ip_version
  [ -n "$ip_version" ] || ip_version="ipv4"
  set_value IP_VERSION "$ip_version"
  echo "Saved speed-test settings."
}

toggle_dry_run() {
  ensure_config
  current="$(get_value DRY_RUN)"
  if [ "$current" = "1" ]; then
    set_bool_or_number DRY_RUN 0
    echo "DRY_RUN=0. Next run will update Cloudflare DNS."
  else
    set_bool_or_number DRY_RUN 1
    echo "DRY_RUN=1. Next run will test only."
  fi
}

run_now() {
  ensure_config
  chmod +x "$RUNNER"
  "$RUNNER"
}

show_log() {
  if [ -f "$LOG_FILE" ]; then
    tail -n 80 "$LOG_FILE"
  else
    echo "No log file yet: $LOG_FILE"
  fi
}

main_menu() {
  ensure_config
  while true; do
    clear 2>/dev/null || true
    echo "cf-dns-speedup menu"
    echo "==================="
    echo "1. Show current config"
    echo "2. Configure Cloudflare"
    echo "3. Configure speed test"
    echo "4. Toggle DRY_RUN"
    echo "5. Run now"
    echo "6. Show log"
    echo "0. Exit"
    echo
    printf "Choose: "
    read -r choice
    case "$choice" in
      1) show_config; pause ;;
      2) setup_cloudflare; pause ;;
      3) setup_speedtest; pause ;;
      4) toggle_dry_run; pause ;;
      5) run_now; pause ;;
      6) show_log; pause ;;
      0) exit 0 ;;
      *) echo "Invalid choice"; pause ;;
    esac
  done
}

main_menu
