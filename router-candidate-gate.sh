#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="${CONFIG_FILE:-$APP_DIR/config.env}"
STAGING_DIR="${CFIP_CANDIDATE_STAGING_DIR:-$APP_DIR/candidate-staging}"
STAGING_FILE="$STAGING_DIR/sidecar-candidates.latest.tsv"
IMPORT_REPORT_FILE="$STAGING_DIR/import.latest.tsv"
LOCK_FILE="${CFIP_CANDIDATE_GATE_LOCK:-/tmp/cfip-candidate-gate.lock}"
PASSWALL_OBSERVE_LOCK="${CFST_PASSWALL_NODE_OBSERVE_LOCK:-/tmp/cf-dns-speedup-passwall-node-observe.lock}"
SCHEMA_VERSION_V1="cfip-sidecar-candidates-v1"
SCHEMA_VERSION_V2="cfip-sidecar-candidates-v2"
EXPECTED_HEADER_V1=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode'
EXPECTED_HEADER_V2=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode\tcandidate_tier'
HARD_OBSERVATION_MIN_MBPS="3.5"
HARD_EXCELLENT_MIN_MBPS="6.5"
MAX_FILE_BYTES="65536"
MAX_CANDIDATES="5"
XRAY_BIN="${CFIP_ROUTER_CANARY_XRAY_BIN:-/usr/bin/xray}"
RUNTIME_JSON="${CFIP_ROUTER_CANARY_RUNTIME_JSON:-/tmp/etc/passwall/acl/default/TCP_UDP_SOCKS.json}"
PASSWALL_CONFIG_FILE="${CFIP_ROUTER_CANARY_PASSWALL_CONFIG:-/etc/config/passwall}"
CANARY_PORT="${CFIP_ROUTER_CANARY_PORT:-19080}"
CANARY_URL="${CFIP_ROUTER_CANARY_TEST_URL:-https://greentrace-speedtest.pages.dev/20mb.bin}"
CANARY_ROUNDS="${CFIP_ROUTER_CANARY_ROUNDS:-2}"
CANARY_MIN_BYTES="${CFIP_ROUTER_CANARY_MIN_BYTES:-20000000}"
CANARY_CONNECT_TIMEOUT="${CFIP_ROUTER_CANARY_CONNECT_TIMEOUT:-12}"
CANARY_TIMEOUT="${CFIP_ROUTER_CANARY_TIMEOUT:-70}"
CANARY_NICE="${CFIP_ROUTER_CANARY_NICE:-10}"
CANARY_HISTORY_FILE="${CFIP_ROUTER_CANARY_HISTORY_FILE:-$APP_DIR/router-candidate-canary-history.tsv}"
CANARY_REPORT_FILE="${CFIP_ROUTER_CANARY_REPORT_FILE:-$APP_DIR/router-candidate-canary.latest.tsv}"
CANARY_QUALIFIED_FILE="${CFIP_ROUTER_CANARY_QUALIFIED_FILE:-$APP_DIR/router-candidate-competition-qualified.tsv}"
CANARY_ALLOWED_FILE="${CFIP_ROUTER_CANARY_ALLOWED_FILE:-}"
PRIMARY_CANARY_HISTORY_FILE="${CFIP_ROUTER_PRIMARY_CANARY_HISTORY_FILE:-$APP_DIR/router-primary-canary-history.tsv}"
PRIMARY_CANARY_REPORT_FILE="${CFIP_ROUTER_PRIMARY_CANARY_REPORT_FILE:-$APP_DIR/router-primary-canary.latest.tsv}"
PRIMARY_CANARY_QUALIFIED_FILE="${CFIP_ROUTER_PRIMARY_CANARY_QUALIFIED_FILE:-$APP_DIR/router-primary-baseline-qualified.tsv}"
CANARY_REQUIRED_DAYS="${CFIP_ROUTER_CANARY_REQUIRED_DAYS:-3}"
CANARY_QUALIFICATION_MAX_AGE_SECONDS="${CFIP_ROUTER_CANARY_QUALIFICATION_MAX_AGE_SECONDS:-604800}"
CANARY_PID=""
CANARY_TMP_DIR=""
CANARY_CONFIG=""
CANARY_CLEANUP_FAILURE=0
VALIDATED_COUNT=0
VALIDATED_EPOCH=0

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

load_config() {
  [ ! -r "$CONFIG_FILE" ] || . "$CONFIG_FILE"
  CFIP_SIDECAR_EXPORT_MAX_AGE_SECONDS="${CFIP_IMPORT_MAX_AGE_SECONDS:-${CFIP_SIDECAR_EXPORT_MAX_AGE_SECONDS:-172800}}"
  CFIP_ROUTER_CANARY_MIN_MBPS="${CFIP_ROUTER_CANARY_MIN_MBPS:-$HARD_OBSERVATION_MIN_MBPS}"
  CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS="${CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS:-4.0}"
  [[ "$CFIP_SIDECAR_EXPORT_MAX_AGE_SECONDS" =~ ^[0-9]+$ ]] \
    && [ "$CFIP_SIDECAR_EXPORT_MAX_AGE_SECONDS" -gt 0 ] \
    && [ "$CFIP_SIDECAR_EXPORT_MAX_AGE_SECONDS" -le 604800 ] \
    || die "candidate export max age must be between 1 and 604800 seconds"
  decimal_at_least "$CFIP_ROUTER_CANARY_MIN_MBPS" "$HARD_OBSERVATION_MIN_MBPS" \
    || die "router canary threshold cannot be below $HARD_OBSERVATION_MIN_MBPS MB/s"
  decimal_at_least "$CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS" 4.0 \
    || die "primary canary threshold cannot be below 4.0 MB/s"
  [[ "$CANARY_PORT" =~ ^[0-9]+$ ]] && [ "$CANARY_PORT" -ge 1024 ] && [ "$CANARY_PORT" -le 65535 ] \
    || die "router canary port is invalid"
  [ "$CANARY_ROUNDS" = "2" ] || die "router canary requires exactly two rounds"
  [[ "$CANARY_MIN_BYTES" =~ ^[0-9]+$ ]] && [ "$CANARY_MIN_BYTES" -ge 20000000 ] \
    || die "router canary byte floor is invalid"
  [[ "$CANARY_REQUIRED_DAYS" =~ ^[0-9]+$ ]] && [ "$CANARY_REQUIRED_DAYS" -ge 3 ] \
    || die "router canary requires at least three distinct passing days"
  [[ "$CANARY_QUALIFICATION_MAX_AGE_SECONDS" =~ ^[0-9]+$ ]] \
    && [ "$CANARY_QUALIFICATION_MAX_AGE_SECONDS" -ge 259200 ] \
    && [ "$CANARY_QUALIFICATION_MAX_AGE_SECONDS" -le 2592000 ] \
    || die "qualification age must be between 3 and 30 days"
  [[ "$CANARY_NICE" =~ ^[0-9]+$ ]] && [ "$CANARY_NICE" -le 19 ] \
    || die "router canary nice value must be between 0 and 19"
  case "$CANARY_URL" in https://*) ;; *) die "router canary URL must use HTTPS" ;; esac
}

prepare_dirs() {
  mkdir -p "$STAGING_DIR"
  chmod 700 "$STAGING_DIR"
}

decimal_value() {
  [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

decimal_at_least() {
  decimal_value "$1" && decimal_value "$2" \
    && awk -v value="$1" -v minimum="$2" 'BEGIN {exit value >= minimum ? 0 : 1}'
}

ipv4_to_int() {
  local ip="$1" a b c d extra octet
  IFS=. read -r a b c d extra <<<"$ip"
  [ -z "${extra:-}" ] && [ -n "${d:-}" ] || return 1
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    [ "$((10#$octet))" -le 255 ] || return 1
  done
  printf '%u\n' "$(((10#$a << 24) | (10#$b << 16) | (10#$c << 8) | 10#$d))"
}

ip_in_cidr() {
  local ip_value base_value bits="$3" mask
  ip_value="$(ipv4_to_int "$1")" || return 1
  base_value="$(ipv4_to_int "$2")" || return 1
  mask=$(( (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF ))
  [ "$((ip_value & mask))" -eq "$((base_value & mask))" ]
}

snapshot_xray_pids() {
  pidof "$(basename "$XRAY_BIN")" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -n
}

snapshot_xray_listeners() {
  netstat -lntp 2>/dev/null | awk 'NR > 2 && /xray/ {print $4 "|" $7}' | sort
}

assert_pids_alive() {
  local pid
  while IFS= read -r pid; do
    [ -z "$pid" ] || kill -0 "$pid" 2>/dev/null || die "existing Xray PID is no longer alive: $pid"
  done < "$1"
}

main_project_lock_busy() {
  local lock="${1:-/tmp/cf-dns-speedup.lock}"
  [ ! -L "$lock" ] || return 0
  [ -e "$lock" ] || return 1
  [ -d "$lock" ] && return 0
  [ -f "$lock" ] || return 0
  flock -n "$lock" -c true >/dev/null 2>&1 && return 1
  return 0
}

assert_no_project_lock() {
  if main_project_lock_busy; then
    die "main CFIP project lock is busy; canary stopped before start"
  fi
  if main_project_lock_busy "$PASSWALL_OBSERVE_LOCK"; then
    die "PassWall observation lock is busy; canary stopped before start"
  fi
}

assert_no_canary_residue() {
  [ -z "$(find /tmp -maxdepth 1 -type d -name 'cfip-router-canary.*' -print -quit 2>/dev/null)" ] \
    || die "a previous canary temporary directory remains; refusing to touch it automatically"
}

assert_runtime_json() {
  [ -f "$RUNTIME_JSON" ] && [ ! -L "$RUNTIME_JSON" ] || die "PassWall runtime JSON is missing or symlinked"
  [ "$(wc -c < "$RUNTIME_JSON" | tr -d ' ')" -le 131072 ] || die "runtime JSON is unexpectedly large"
  jq -e '([.outbounds[] | select(.protocol == "vmess" and (.settings.address | type == "string"))] | length) == 1' \
    "$RUNTIME_JSON" >/dev/null || die "runtime JSON has no supported single VMess address"
}

validate_allowed_candidate_file() {
  local candidate epoch source extra count=0 seen=""
  [ -n "$CANARY_ALLOWED_FILE" ] || die "retained candidate allowlist is missing"
  [ -f "$CANARY_ALLOWED_FILE" ] && [ ! -L "$CANARY_ALLOWED_FILE" ] \
    || die "retained candidate allowlist must be a regular non-symlink file"
  [ "$(wc -c <"$CANARY_ALLOWED_FILE" | tr -d ' ')" -le 4096 ] \
    || die "retained candidate allowlist is unexpectedly large"
  [ "$(head -n 1 "$CANARY_ALLOWED_FILE")" = $'candidate_ip\tsource_export_epoch\tsource' ] \
    || die "retained candidate allowlist header is invalid"
  while IFS=$'\t' read -r candidate epoch source extra; do
    [ -n "$candidate" ] || continue
    [ -z "${extra:-}" ] || die "retained candidate allowlist has extra fields"
    is_cloudflare_ipv4 "$candidate" || die "retained candidate allowlist contains a non-Cloudflare IPv4"
    [[ "$epoch" =~ ^[0-9]{10}$ ]] && [ "$epoch" = "$VALIDATED_EPOCH" ] \
      || die "retained candidate allowlist is not bound to the current export"
    case "$source" in retained|staging) ;; *) die "retained candidate allowlist source is invalid" ;; esac
    case " $seen " in *" $candidate "*) die "retained candidate allowlist contains a duplicate IP" ;; esac
    seen="$seen $candidate"
    count=$((count + 1))
    [ "$count" -le 3 ] || die "retained candidate allowlist contains more than three entries"
  done < <(tail -n +2 "$CANARY_ALLOWED_FILE")
}

candidate_from_staging() {
  local requested="${1:-}" candidate
  validate_export_file "$STAGING_FILE"
  [ "$VALIDATED_COUNT" -gt 0 ] || die "staging queue has no qualified candidate"
  if [ -n "$requested" ]; then
    is_cloudflare_ipv4 "$requested" || die "requested canary candidate is not a Cloudflare IPv4"
    candidate="$(awk -F '\t' -v ip="$requested" 'NR > 1 && $4 == ip {print $4; exit}' "$STAGING_FILE")"
    if [ "$candidate" != "$requested" ]; then
      validate_allowed_candidate_file
      candidate="$(awk -F '\t' -v ip="$requested" 'NR > 1 && $1 == ip {print $1; exit}' "$CANARY_ALLOWED_FILE")"
      [ "$candidate" = "$requested" ] || die "requested candidate is not in the current canary plan"
    fi
  else
    candidate="$(awk -F '\t' 'NR == 2 {print $4; exit}' "$STAGING_FILE")"
  fi
  printf '%s\n' "$candidate"
}

candidate_source_epoch() {
  local candidate="$1" epoch
  epoch="$(awk -F '\t' -v ip="$candidate" 'NR > 1 && $4 == ip {print $2; exit}' "$STAGING_FILE")"
  if [ -z "$epoch" ] && [ -n "$CANARY_ALLOWED_FILE" ]; then
    epoch="$(awk -F '\t' -v ip="$candidate" 'NR > 1 && $1 == ip {print $2; exit}' "$CANARY_ALLOWED_FILE")"
  fi
  [ -n "$epoch" ] || die "candidate source epoch is missing"
  printf '%s\n' "$epoch"
}

proxy_tag_from_runtime() {
  jq -r '.outbounds[] | select(.protocol == "vmess" and (.settings.address | type == "string")) | .tag' \
    "$RUNTIME_JSON"
}

cleanup_canary() {
  local command_line
  if [ -n "$CANARY_PID" ] && kill -0 "$CANARY_PID" 2>/dev/null; then
    command_line="$(tr '\000' ' ' < "/proc/$CANARY_PID/cmdline" 2>/dev/null || true)"
    if [ -z "$command_line" ]; then
      :
    elif [[ "$command_line" == *"$CANARY_CONFIG"* ]] && [[ "$command_line" == *"$XRAY_BIN"* ]]; then
      kill "$CANARY_PID" 2>/dev/null || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$CANARY_PID" 2>/dev/null || break
        sleep 1
      done
      if kill -0 "$CANARY_PID" 2>/dev/null; then
        command_line="$(tr '\000' ' ' < "/proc/$CANARY_PID/cmdline" 2>/dev/null || true)"
        if [ -z "$command_line" ]; then
          :
        elif [[ "$command_line" == *"$CANARY_CONFIG"* ]] && [[ "$command_line" == *"$XRAY_BIN"* ]]; then
          kill -KILL "$CANARY_PID" 2>/dev/null || true
          for _ in 1 2 3 4 5 6 7 8 9 10; do
            kill -0 "$CANARY_PID" 2>/dev/null || break
            sleep 1
          done
          kill -0 "$CANARY_PID" 2>/dev/null && CANARY_CLEANUP_FAILURE=1
        else
          CANARY_CLEANUP_FAILURE=1
        fi
      fi
    else
      CANARY_CLEANUP_FAILURE=1
    fi
  fi
  if [ "$CANARY_CLEANUP_FAILURE" -eq 0 ] && [ -n "$CANARY_PID" ]; then
    wait "$CANARY_PID" 2>/dev/null || true
    CANARY_PID=""
  fi
  if [ -n "$CANARY_TMP_DIR" ]; then
    rm -rf "$CANARY_TMP_DIR"
    CANARY_TMP_DIR=""
  fi
}

trap cleanup_canary EXIT INT TERM

render_canary_config() {
  local candidate="$1" proxy_tag="$2"
  CANARY_TMP_DIR="$(mktemp -d /tmp/cfip-router-canary.XXXXXX)"
  chmod 700 "$CANARY_TMP_DIR"
  CANARY_CONFIG="$CANARY_TMP_DIR/config.json"
  jq --arg ip "$candidate" --arg tag "$proxy_tag" --argjson port "$CANARY_PORT" '
    .outbounds as $outbounds
    | {
        log: {loglevel: "warning"},
        inbounds: [{listen: "127.0.0.1", port: $port, protocol: "socks",
          settings: {auth: "noauth", udp: false}, tag: "cfip-isolated-canary"}],
        outbounds: ($outbounds | map(if .tag == $tag then .settings.address = $ip else . end)),
        routing: {domainStrategy: "AsIs", rules: [{type: "field",
          inboundTag: ["cfip-isolated-canary"], outboundTag: $tag}]}
      }
  ' "$RUNTIME_JSON" > "$CANARY_CONFIG"
  chmod 600 "$CANARY_CONFIG"
  "$XRAY_BIN" run -test -c "$CANARY_CONFIG" >/dev/null 2>&1 \
    || die "isolated Xray configuration test failed"
}

assert_canary_port_free() {
  netstat -lnt 2>/dev/null | awk -v port=":$CANARY_PORT" '$4 ~ port "$" {found=1} END {exit found ? 1 : 0}' \
    || die "isolated canary port is already in use: $CANARY_PORT"
}

start_canary() {
  nice -n "$CANARY_NICE" "$XRAY_BIN" run -c "$CANARY_CONFIG" >"$CANARY_TMP_DIR/xray.log" 2>&1 &
  CANARY_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "$CANARY_PID" 2>/dev/null || die "isolated Xray exited before its SOCKS port opened"
    if netstat -lntp 2>/dev/null | awk -v port=":$CANARY_PORT" -v pid="$CANARY_PID" \
      '$4 ~ port "$" && $7 ~ pid "/xray" {found=1} END {exit found ? 0 : 1}'; then
      return 0
    fi
    sleep 1
  done
  die "isolated Xray did not open its private SOCKS port"
}

curl_round() {
  local raw
  raw="$(nice -n "$CANARY_NICE" curl -sS -L --socks5-hostname "127.0.0.1:$CANARY_PORT" \
    --connect-timeout "$CANARY_CONNECT_TIMEOUT" --max-time "$CANARY_TIMEOUT" \
    -o /dev/null -w '%{http_code}\t%{size_download}\t%{speed_download}' \
    "$CANARY_URL" 2>/dev/null)" || raw=$'000\t0\t0'
  printf '%s\n' "$raw"
}

speed_from_bps() {
  awk -v bps="$1" 'BEGIN {printf "%.2f", (bps + 0) / 1048576}'
}

refresh_qualified_report() {
  local history_file="$1" qualified_file="$2" minimum="$3" qualified_status="$4" path_mode="$5" error_label="$6"
  local temporary="$qualified_file.tmp.$$"
  mkdir -p "$(dirname "$qualified_file")"
  if [ ! -s "$history_file" ]; then
    printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n' >"$temporary"
    chmod 600 "$temporary"
    mv -f "$temporary" "$qualified_file"
    return 0
  fi
  awk -F '\t' -v required="$CANARY_REQUIRED_DAYS" -v minimum="$minimum" \
      -v min_bytes="$CANARY_MIN_BYTES" -v now="$(date +%s)" \
      -v max_age="$CANARY_QUALIFICATION_MAX_AGE_SECONDS" -v qualified_status="$qualified_status" \
      -v path_mode="$path_mode" '
    function reset_streak(ip) {
      streak[ip]=0; streak_exports[ip]=0; streak_min[ip]=""; streak_avg_sum[ip]=0; streak_rows[ip]=0
    }
    function finalize_day(ip) {
      if (day_date[ip] == "") return
      if (day_ok[ip] && day_rows[ip] > 0 && day_exports[ip] > 0 && day_min[ip] >= minimum) {
        streak[ip]++
        streak_exports[ip] += day_exports[ip]
        if (streak_min[ip] == "" || day_min[ip] < streak_min[ip]) streak_min[ip]=day_min[ip]
        streak_avg_sum[ip] += day_avg_sum[ip]
        streak_rows[ip] += day_rows[ip]
        latest[ip]=day_latest[ip]
      } else reset_streak(ip)
      day_date[ip]=""; day_ok[ip]=1; day_rows[ip]=0; day_min[ip]=""; day_avg_sum[ip]=0; day_exports[ip]=0
    }
    NR == 1 {next}
    ($3 + 0) <= now + 300 && now - ($3 + 0) <= max_age {
      ip=$2; date=substr($1, 1, 10); ips[ip]=1
      if (day_date[ip] != "" && day_date[ip] != date) finalize_day(ip)
      if (day_date[ip] == "") {day_date[ip]=date; day_ok[ip]=1}
      row_ok=($12 == "pass" && $8 == "200" && $9 == "200" && ($6 + 0) >= minimum \
        && ($10 + 0) >= min_bytes && ($11 + 0) >= min_bytes)
      if (!row_ok) day_ok[ip]=0
      day_rows[ip]++
      if (day_min[ip] == "" || ($6 + 0) < day_min[ip]) day_min[ip]=$6+0
      day_avg_sum[ip]+=$7+0
      day_latest[ip]=$1
      source_key=ip SUBSEP $3
      if (!source_seen[source_key]++) day_exports[ip]++
    }
    END {
      print "candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode"
      for (ip in ips) {
        finalize_day(ip)
        if (streak[ip] >= required && streak_exports[ip] >= required && streak_rows[ip] > 0)
          printf "%s\t%d\t%d\t%.2f\t%.2f\t%s\t%s\t%s\n", \
            ip, streak[ip], streak_exports[ip], streak_min[ip], streak_avg_sum[ip] / streak_rows[ip], \
            latest[ip], qualified_status, path_mode
      }
    }
  ' "$history_file" 2>/dev/null > "$temporary" || {
    rm -f "$temporary"
    die "cannot refresh $error_label qualification report"
  }
  chmod 600 "$temporary"
  mv -f "$temporary" "$qualified_file"
}

refresh_competition_qualified() {
  refresh_qualified_report "$CANARY_HISTORY_FILE" "$CANARY_QUALIFIED_FILE" \
    "$CFIP_ROUTER_CANARY_MIN_MBPS" competition_qualified router_isolated_xray competition
}

refresh_primary_qualified() {
  refresh_qualified_report "$PRIMARY_CANARY_HISTORY_FILE" "$PRIMARY_CANARY_QUALIFIED_FILE" \
    "$CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS" primary_baseline_qualified router_primary_isolated_xray primary
}

run_isolated_canary() {
  local mode="$1" requested="${2:-}" candidate proxy_tag baseline_pids baseline_listeners
  local baseline_config_sha baseline_runtime_sha baseline_staging_sha="" after_pids after_listeners source_epoch
  local round raw http bytes bps speed1=0 speed2=0 bytes1=0 bytes2=0
  local http1=000 http2=000 min_speed avg_speed status observed_at report_tmp
  local threshold report_file history_file path_mode protect_staging=0

  load_config
  need_cmd jq; need_cmd curl; need_cmd netstat; need_cmd pidof; need_cmd sha256sum; need_cmd nice
  prepare_dirs
  acquire_lock
  assert_no_project_lock
  assert_no_canary_residue
  baseline_pids="$(snapshot_xray_pids)"
  [ -n "$baseline_pids" ] || die "no existing PassWall Xray process was found"
  baseline_listeners="$(snapshot_xray_listeners)"
  assert_pids_alive <(printf '%s\n' "$baseline_pids")
  baseline_config_sha="$(sha256sum "$PASSWALL_CONFIG_FILE" 2>/dev/null | awk '{print $1}')"
  [ -n "$baseline_config_sha" ] || die "PassWall UCI config is not readable"
  assert_runtime_json
  baseline_runtime_sha="$(sha256sum "$RUNTIME_JSON" | awk '{print $1}')"
  case "$mode" in
    candidate)
      baseline_staging_sha="$(sha256sum "$STAGING_FILE" | awk '{print $1}')"
      candidate="$(candidate_from_staging "$requested")"
      source_epoch="$(candidate_source_epoch "$candidate")"
      threshold="$CFIP_ROUTER_CANARY_MIN_MBPS"
      report_file="$CANARY_REPORT_FILE"
      history_file="$CANARY_HISTORY_FILE"
      path_mode=router_isolated_xray
      protect_staging=1
      ;;
    primary)
      [ -n "$requested" ] || die "primary canary requires an IP"
      is_cloudflare_ipv4 "$requested" || die "primary canary target is not a Cloudflare IPv4"
      candidate="$requested"
      source_epoch="$(date +%s)"
      threshold="$CFIP_ROUTER_PRIMARY_CANARY_MIN_MBPS"
      report_file="$PRIMARY_CANARY_REPORT_FILE"
      history_file="$PRIMARY_CANARY_HISTORY_FILE"
      path_mode=router_primary_isolated_xray
      ;;
    *) die "unsupported isolated canary mode" ;;
  esac
  proxy_tag="$(proxy_tag_from_runtime)"
  [ -n "$proxy_tag" ] || die "runtime VMess outbound tag is empty"
  assert_canary_port_free
  render_canary_config "$candidate" "$proxy_tag"
  start_canary

  round=1
  while [ "$round" -le "$CANARY_ROUNDS" ]; do
    raw="$(curl_round)"
    IFS=$'\t' read -r http bytes bps <<<"$raw"
    speed="$(speed_from_bps "${bps:-0}")"
    if [ "$round" -eq 1 ]; then http1="${http:-000}"; bytes1="${bytes:-0}"; speed1="$speed"; fi
    if [ "$round" -eq 2 ]; then http2="${http:-000}"; bytes2="${bytes:-0}"; speed2="$speed"; fi
    round=$((round + 1))
  done
  [[ "$bytes1" =~ ^[0-9]+$ ]] || bytes1=0
  [[ "$bytes2" =~ ^[0-9]+$ ]] || bytes2=0

  cleanup_canary
  [ "$CANARY_CLEANUP_FAILURE" -eq 0 ] || die "isolated Xray cleanup was not proven safe"
  CANARY_PID=""
  after_pids="$(snapshot_xray_pids)"
  after_listeners="$(snapshot_xray_listeners)"
  [ "$after_pids" = "$baseline_pids" ] || die "existing Xray PID set changed during isolated canary"
  [ "$after_listeners" = "$baseline_listeners" ] || die "existing Xray listeners changed during isolated canary"
  assert_pids_alive <(printf '%s\n' "$baseline_pids")
  [ "$(sha256sum "$PASSWALL_CONFIG_FILE" | awk '{print $1}')" = "$baseline_config_sha" ] \
    || die "PassWall UCI config changed during isolated canary"
  [ "$(sha256sum "$RUNTIME_JSON" | awk '{print $1}')" = "$baseline_runtime_sha" ] \
    || die "PassWall runtime JSON changed during isolated canary"
  if [ "$protect_staging" -eq 1 ]; then
    [ "$(sha256sum "$STAGING_FILE" | awk '{print $1}')" = "$baseline_staging_sha" ] \
      || die "candidate staging file changed during isolated canary"
  fi

  min_speed="$(awk -v a="$speed1" -v b="$speed2" 'BEGIN {printf "%.2f", a < b ? a : b}')"
  avg_speed="$(awk -v a="$speed1" -v b="$speed2" 'BEGIN {printf "%.2f", (a + b) / 2}')"
  status="low"
  if [ "$http1" = "200" ] && [ "$http2" = "200" ] \
    && [ "$bytes1" -ge "$CANARY_MIN_BYTES" ] && [ "$bytes2" -ge "$CANARY_MIN_BYTES" ] \
    && decimal_at_least "$min_speed" "$threshold"; then
    status="pass"
  fi
  observed_at="$(date '+%F %T')"
  mkdir -p "$(dirname "$report_file")"
  report_tmp="$report_file.tmp.$$"
  printf 'observed_at\tcandidate_ip\tsource_export_epoch\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tbytes1\tbytes2\tstatus\tpath_mode\n' > "$report_tmp"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$observed_at" "$candidate" "$source_epoch" "$speed1" "$speed2" "$min_speed" "$avg_speed" \
    "$http1" "$http2" "$bytes1" "$bytes2" "$status" "$path_mode" >> "$report_tmp"
  chmod 600 "$report_tmp"
  mv -f "$report_tmp" "$report_file"
  if [ ! -f "$history_file" ]; then
    printf 'observed_at\tcandidate_ip\tsource_export_epoch\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tbytes1\tbytes2\tstatus\tpath_mode\n' > "$history_file"
    chmod 600 "$history_file"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$observed_at" "$candidate" "$source_epoch" "$speed1" "$speed2" "$min_speed" "$avg_speed" \
    "$http1" "$http2" "$bytes1" "$bytes2" "$status" "$path_mode" >> "$history_file"
  case "$mode" in
    candidate) refresh_competition_qualified ;;
    primary) refresh_primary_qualified ;;
  esac
  log "isolated router $mode canary complete: candidate=$candidate min=${min_speed}MB/s status=$status; existing PassWall was not stopped or changed"
}

canary_candidate() {
  run_isolated_canary candidate "${1:-}"
}

primary_canary_candidate() {
  run_isolated_canary primary "${1:-}"
}

canary_plan() {
  local requested="${1:-}" candidate proxy_tag baseline_pids baseline_listeners
  local baseline_config_sha baseline_runtime_sha baseline_staging_sha
  load_config
  need_cmd jq; need_cmd netstat; need_cmd pidof; need_cmd sha256sum
  prepare_dirs
  acquire_lock
  assert_no_project_lock
  assert_no_canary_residue
  baseline_pids="$(snapshot_xray_pids)"
  [ -n "$baseline_pids" ] || die "no existing PassWall Xray process was found"
  baseline_listeners="$(snapshot_xray_listeners)"
  assert_pids_alive <(printf '%s\n' "$baseline_pids")
  baseline_config_sha="$(sha256sum "$PASSWALL_CONFIG_FILE" 2>/dev/null | awk '{print $1}')"
  [ -n "$baseline_config_sha" ] || die "PassWall UCI config is not readable"
  assert_runtime_json
  baseline_runtime_sha="$(sha256sum "$RUNTIME_JSON" | awk '{print $1}')"
  baseline_staging_sha="$(sha256sum "$STAGING_FILE" | awk '{print $1}')"
  candidate="$(candidate_from_staging "$requested")"
  proxy_tag="$(proxy_tag_from_runtime)"
  [ -n "$proxy_tag" ] || die "runtime VMess outbound tag is empty"
  assert_canary_port_free
  render_canary_config "$candidate" "$proxy_tag"
  [ "$(snapshot_xray_pids)" = "$baseline_pids" ] || die "Xray PID changed during canary plan"
  [ "$(snapshot_xray_listeners)" = "$baseline_listeners" ] || die "Xray listeners changed during canary plan"
  [ "$(sha256sum "$PASSWALL_CONFIG_FILE" | awk '{print $1}')" = "$baseline_config_sha" ] \
    || die "PassWall UCI config changed during canary plan"
  [ "$(sha256sum "$RUNTIME_JSON" | awk '{print $1}')" = "$baseline_runtime_sha" ] \
    || die "PassWall runtime JSON changed during canary plan"
  [ "$(sha256sum "$STAGING_FILE" | awk '{print $1}')" = "$baseline_staging_sha" ] \
    || die "candidate staging file changed during canary plan"
  cleanup_canary
  CANARY_PID=""
  printf 'canary_plan=ok\tcandidate=%s\texisting_xray_unchanged=1\tpasswall_restart=0\n' "$candidate"
}

refresh_qualification_command() {
  load_config
  mkdir -p "$(dirname "$CANARY_QUALIFIED_FILE")"
  if [ -s "$CANARY_HISTORY_FILE" ]; then
    refresh_competition_qualified
  else
    printf 'candidate_ip\tpass_days\tpass_exports\tlatest_min_MBps\tlatest_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n' \
      > "$CANARY_QUALIFIED_FILE"
    chmod 600 "$CANARY_QUALIFIED_FILE"
  fi
  awk 'NR > 1 {count++} END {print "competition_qualified_count=" (count + 0)}' "$CANARY_QUALIFIED_FILE"
}

refresh_primary_qualification_command() {
  load_config
  mkdir -p "$(dirname "$PRIMARY_CANARY_QUALIFIED_FILE")"
  if [ -s "$PRIMARY_CANARY_HISTORY_FILE" ]; then
    refresh_primary_qualified
  else
    printf 'candidate_ip\tconsecutive_pass_days\tpass_exports\twindow_min_MBps\twindow_avg_MBps\tlast_observed_at\tstatus\tpath_mode\n' \
      > "$PRIMARY_CANARY_QUALIFIED_FILE"
    chmod 600 "$PRIMARY_CANARY_QUALIFIED_FILE"
  fi
  awk 'NR > 1 {count++} END {print "primary_baseline_qualified_count=" (count + 0)}' \
    "$PRIMARY_CANARY_QUALIFIED_FILE"
}



is_cloudflare_ipv4() {
  local ip="$1" cidr base bits
  ipv4_to_int "$ip" >/dev/null || return 1
  for cidr in \
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 \
    141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 \
    197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 \
    104.24.0.0/14 172.64.0.0/13 131.0.72.0/22; do
    base="${cidr%/*}"
    bits="${cidr#*/}"
    ip_in_cidr "$ip" "$base" "$bits" && return 0
  done
  return 1
}

validate_export_file() {
  local source="$1" size header schema expected_fields now epoch observed ip direct round1 round2 minimum average
  local http1 http2 status path tier extra line_count row_limit first_epoch="" invalid_bytes
  declare -A seen=()

  [ -f "$source" ] && [ ! -L "$source" ] || die "candidate export must be a regular non-symlink file"
  size="$(wc -c < "$source" | tr -d ' ')"
  [ "$size" -gt 0 ] && [ "$size" -le "$MAX_FILE_BYTES" ] \
    || die "candidate export size is outside the allowed range"
  invalid_bytes="$(LC_ALL=C tr -d '\011\012\040-\176' < "$source" | wc -c | tr -d ' ')"
  [ "$invalid_bytes" -eq 0 ] || die "candidate export contains non-ASCII control data"
  need_cmd tail
  need_cmd tr
  need_cmd wc
  [ "$(tail -c 1 "$source" | tr -d '\n' | wc -c | tr -d ' ')" = "0" ] \
    || die "candidate export must end with a newline"
  header="$(sed -n '1p' "$source")"
  case "$header" in
    "$EXPECTED_HEADER_V1") schema="$SCHEMA_VERSION_V1"; expected_fields=13; row_limit="$MAX_CANDIDATES" ;;
    "$EXPECTED_HEADER_V2") schema="$SCHEMA_VERSION_V2"; expected_fields=14; row_limit=3 ;;
    *) die "candidate export header or schema contract is invalid" ;;
  esac
  awk -F '\t' -v expected="$expected_fields" 'NF != expected {exit 1}' "$source" \
    || die "candidate export has an invalid field count"
  line_count="$(wc -l < "$source" | tr -d ' ')"
  [ "$line_count" -le "$((row_limit + 1))" ] || die "candidate export has too many rows"

  now="$(date +%s)"
  VALIDATED_COUNT=0
  VALIDATED_EPOCH=0
  while IFS=$'\t' read -r row_schema epoch observed ip direct round1 round2 minimum average \
      http1 http2 status path tier extra; do
    [ "$row_schema" = "$schema" ] || die "candidate row schema version is invalid"
    [[ "$epoch" =~ ^[0-9]{10}$ ]] || die "candidate export epoch is invalid"
    [ "$epoch" -le "$((now + 300))" ] || die "candidate export epoch is in the future"
    [ "$((now - epoch))" -le "$CFIP_SIDECAR_EXPORT_MAX_AGE_SECONDS" ] \
      || die "candidate export is stale"
    [ -z "$first_epoch" ] && first_epoch="$epoch"
    [ "$epoch" = "$first_epoch" ] || die "candidate rows have mixed export epochs"
    [[ "$observed" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] \
      || die "candidate observed_at is invalid"
    is_cloudflare_ipv4 "$ip" || die "candidate is outside Cloudflare IPv4 ranges: $ip"
    [ -z "${seen[$ip]+x}" ] || die "candidate export contains a duplicate IP: $ip"
    seen[$ip]=1
    decimal_value "$direct" && decimal_value "$round1" && decimal_value "$round2" \
      && decimal_value "$minimum" && decimal_value "$average" \
      || die "candidate speed fields are invalid"
    awk -v a="$round1" -v b="$round2" -v m="$minimum" -v avg="$average" '
      BEGIN {
        expected_min = a < b ? a : b
        expected_avg = (a + b) / 2
        min_diff = m - expected_min; if (min_diff < 0) min_diff = -min_diff
        avg_diff = avg - expected_avg; if (avg_diff < 0) avg_diff = -avg_diff
        exit (min_diff <= 0.011 && avg_diff <= 0.011) ? 0 : 1
      }
    ' || die "candidate min/average values are inconsistent"
    [ "$http1" = "200" ] && [ "$http2" = "200" ] \
      || die "candidate did not pass both HTTP rounds"
    [ "$path" = "sidecar_proxy" ] || die "candidate path mode is invalid"
    if [ "$schema" = "$SCHEMA_VERSION_V1" ]; then
      decimal_at_least "$minimum" "$HARD_EXCELLENT_MIN_MBPS" \
        || die "v1 candidate is below the hard $HARD_EXCELLENT_MIN_MBPS MB/s threshold"
      [ "$status" = "pass" ] && [ -z "${tier:-}" ] \
        || die "v1 candidate status is invalid"
    else
      decimal_at_least "$minimum" "$HARD_OBSERVATION_MIN_MBPS" \
        || die "v2 candidate is below the hard $HARD_OBSERVATION_MIN_MBPS MB/s threshold"
      if decimal_at_least "$minimum" "$HARD_EXCELLENT_MIN_MBPS"; then
        [ "$tier" = "excellent" ] && [ "$status" = "pass" ] \
          || die "v2 excellent candidate classification is inconsistent"
      else
        [ "$tier" = "observation" ] && [ "$status" = "low" ] \
          || die "v2 observation candidate classification is inconsistent"
      fi
    fi
    [ -z "${extra:-}" ] || die "candidate row contains extra fields"
    VALIDATED_COUNT=$((VALIDATED_COUNT + 1))
  done < <(tail -n +2 "$source")
  [ "$VALIDATED_COUNT" -le "$row_limit" ] || die "candidate export exceeds the row limit"
  [ -z "$first_epoch" ] || VALIDATED_EPOCH="$first_epoch"
}
acquire_lock() {
  need_cmd flock
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "another candidate gate operation is running"
}

import_candidates() {
  local source="${1:-}" temporary report_tmp digest imported_at
  [ -n "$source" ] || die "import requires a candidate export file"
  load_config
  prepare_dirs
  acquire_lock
  validate_export_file "$source"
  temporary="$(mktemp "$STAGING_DIR/.sidecar-candidates.XXXXXX")"
  report_tmp="$(mktemp "$STAGING_DIR/.import-report.XXXXXX")"
  trap 'rm -f "${temporary:-}" "${report_tmp:-}"' RETURN
  cp "$source" "$temporary"
  chmod 600 "$temporary"
  digest="$(sha256sum "$temporary" | awk '{print $1}')"
  imported_at="$(date '+%F %T')"
  printf 'imported_at\tsource_export_epoch\tcandidate_count\tsource_sha256\tstatus\n' > "$report_tmp"
  printf '%s\t%s\t%s\t%s\taccepted_staging_only\n' \
    "$imported_at" "$VALIDATED_EPOCH" "$VALIDATED_COUNT" "$digest" >> "$report_tmp"
  chmod 600 "$report_tmp"
  mv -f "$temporary" "$STAGING_FILE"
  mv -f "$report_tmp" "$IMPORT_REPORT_FILE"
  sync "$STAGING_FILE" "$IMPORT_REPORT_FILE" 2>/dev/null || sync
  trap - RETURN
  log "candidate import complete: count=$VALIDATED_COUNT; staging only; no PassWall or DNS change"
}

list_candidates() {
  load_config
  prepare_dirs
  [ -r "$STAGING_FILE" ] || die "no staged candidate export exists"
  validate_export_file "$STAGING_FILE"
  printf 'candidate_ip\tmin_MBps\tavg_MBps\tobserved_at\n'
  awk -F '\t' 'NR > 1 {print $4 "\t" $8 "\t" $9 "\t" $3}' "$STAGING_FILE"
}

main() {
  need_cmd awk
  need_cmd sha256sum
  case "${1:-}" in
    import) import_candidates "${2:-}" ;;
    list) list_candidates ;;
    canary-plan) canary_plan "${2:-}" ;;
    canary) canary_candidate "${2:-}" ;;
    primary-canary) primary_canary_candidate "${2:-}" ;;
    qualify) refresh_qualification_command ;;
    primary-qualify) refresh_primary_qualification_command ;;
    validate-candidate) is_cloudflare_ipv4 "${2:-}" || exit 1 ;;
    *) echo "Usage: $0 {import FILE|list|canary-plan [IP]|canary [IP]|primary-canary IP|qualify|primary-qualify|validate-candidate IP}" >&2; exit 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
