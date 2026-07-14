#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONFIG_FILE="${SIDECAR_CONFIG_FILE:-/etc/cfip-sidecar/sidecar.env}"
[ -r "$CONFIG_FILE" ] && . "$CONFIG_FILE"

SIDECAR_IP="${SIDECAR_IP:-192.168.1.252}"
SIDECAR_SUBNET="${SIDECAR_SUBNET:-192.168.1.0/24}"
SIDECAR_GATEWAY="${SIDECAR_GATEWAY:-192.168.1.254}"
SIDECAR_PARENT_IF="${SIDECAR_PARENT_IF:-ens160}"
SIDECAR_NETWORK="${SIDECAR_NETWORK:-cfip-direct}"
SIDECAR_RUNTIME_IMAGE="${SIDECAR_RUNTIME_IMAGE:-cfip-sidecar-runtime:20260714}"
SIDECAR_ASSET_DIR="${SIDECAR_ASSET_DIR:-/opt/cfip-sidecar/assets}"
SIDECAR_DATA_DIR="${SIDECAR_DATA_DIR:-/var/lib/cfip-sidecar}"
SIDECAR_RUN_DIR="${SIDECAR_RUN_DIR:-/run/cfip-sidecar}"
SIDECAR_REQUIRED_CONTAINERS="${SIDECAR_REQUIRED_CONTAINERS:-k12-reg sub2api sub2api-postgres sub2api-redis}"

SIDECAR_MAX_LOAD1="${SIDECAR_MAX_LOAD1:-1.0}"
SIDECAR_MIN_AVAILABLE_MB="${SIDECAR_MIN_AVAILABLE_MB:-4096}"
SIDECAR_MIN_DISK_MB="${SIDECAR_MIN_DISK_MB:-10240}"
SIDECAR_PATH_CHECK_URL="${SIDECAR_PATH_CHECK_URL:-https://www.cloudflare.com/cdn-cgi/trace}"
SIDECAR_REQUIRE_DIFFERENT_PUBLIC_IP="${SIDECAR_REQUIRE_DIFFERENT_PUBLIC_IP:-1}"

SIDECAR_TEST_URL="${SIDECAR_TEST_URL:-https://greentrace-speedtest.pages.dev/20mb.bin}"
SIDECAR_DIRECT_INITIAL_COUNT="${SIDECAR_DIRECT_INITIAL_COUNT:-50}"
SIDECAR_DIRECT_STEP="${SIDECAR_DIRECT_STEP:-50}"
SIDECAR_DIRECT_MAX_COUNT="${SIDECAR_DIRECT_MAX_COUNT:-100}"
SIDECAR_DIRECT_MIN_MBPS="${SIDECAR_DIRECT_MIN_MBPS:-8}"
SIDECAR_DIRECT_REQUIRED="${SIDECAR_DIRECT_REQUIRED:-5}"
SIDECAR_CANDIDATE_LIMIT="${SIDECAR_CANDIDATE_LIMIT:-5}"
SIDECAR_PROXY_MIN_MBPS="${SIDECAR_PROXY_MIN_MBPS:-6.5}"
SIDECAR_PROXY_MIN_BYTES="${SIDECAR_PROXY_MIN_BYTES:-20000000}"
SIDECAR_PROXY_ROUNDS="${SIDECAR_PROXY_ROUNDS:-2}"

SIDECAR_CFST_THREADS="${SIDECAR_CFST_THREADS:-16}"
SIDECAR_CFST_TIMEOUT="${SIDECAR_CFST_TIMEOUT:-4}"
SIDECAR_CFST_MAX_LATENCY="${SIDECAR_CFST_MAX_LATENCY:-220}"
SIDECAR_CFST_MIN_LATENCY="${SIDECAR_CFST_MIN_LATENCY:-0}"
SIDECAR_CFST_DOWNLOAD_TIMEOUT="${SIDECAR_CFST_DOWNLOAD_TIMEOUT:-25}"
SIDECAR_CFST_TOTAL_TIMEOUT="${SIDECAR_CFST_TOTAL_TIMEOUT:-1800}"

SIDECAR_CONTAINER_CPUS="${SIDECAR_CONTAINER_CPUS:-1.0}"
SIDECAR_XRAY_MEMORY="${SIDECAR_XRAY_MEMORY:-384m}"
SIDECAR_SCAN_MEMORY="${SIDECAR_SCAN_MEMORY:-512m}"
SIDECAR_CURL_MEMORY="${SIDECAR_CURL_MEMORY:-128m}"
SIDECAR_PIDS_LIMIT="${SIDECAR_PIDS_LIMIT:-64}"
CREDENTIAL_SOURCE="${CREDENTIAL_SOURCE:-${CREDENTIALS_DIRECTORY:-}/xray-source}"

DOCKER_BIN="${DOCKER_BIN:-docker}"
CURL_BIN="${CURL_BIN:-curl}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
LOCK_FILE="$SIDECAR_RUN_DIR/sidecar.lock"
LOG_FILE="$SIDECAR_DATA_DIR/sidecar.log"
ACTIVE_CONTAINERS=""

log() {
  mkdir -p "$SIDECAR_DATA_DIR"
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

die() {
  log "ERROR: $*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

cleanup() {
  local name
  for name in $ACTIVE_CONTAINERS; do
    "$DOCKER_BIN" rm -f "$name" >/dev/null 2>&1 || true
  done
  find "$SIDECAR_RUN_DIR" -maxdepth 1 -type f -name 'xray-*.json' -delete 2>/dev/null || true
}
trap cleanup EXIT INT TERM

prepare_dirs() {
  mkdir -p "$SIDECAR_RUN_DIR" "$SIDECAR_DATA_DIR/observations"
  chmod 700 "$SIDECAR_RUN_DIR" "$SIDECAR_DATA_DIR" "$SIDECAR_DATA_DIR/observations"
}

acquire_lock() {
  prepare_dirs
  exec 9>"$LOCK_FILE"
  flock -n 9 || die "another sidecar run holds $LOCK_FILE"
}

ollama_is_idle() {
  "$CURL_BIN" -fsS --connect-timeout 3 --max-time 5 http://127.0.0.1:11434/api/ps \
    | "$PYTHON_BIN" -c 'import json,sys; raise SystemExit(0 if not json.load(sys.stdin).get("models") else 1)'
}

container_is_healthy() {
  local name="$1" state
  state="$("$DOCKER_BIN" inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$name" 2>/dev/null || true)"
  case "$state" in
    running\|healthy|running\|none) return 0 ;;
    *) return 1 ;;
  esac
}

gate_check() {
  local load1 available_mb disk_mb name
  "$DOCKER_BIN" info >/dev/null 2>&1 || die "Docker is unavailable"
  ollama_is_idle || die "Ollama has a resident model; sidecar yields"
  load1="$(awk '{print $1}' /proc/loadavg)"
  awk -v value="$load1" -v max="$SIDECAR_MAX_LOAD1" 'BEGIN {exit value < max ? 0 : 1}' \
    || die "load1 $load1 is not below $SIDECAR_MAX_LOAD1"
  available_mb="$(awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo)"
  [ "$available_mb" -ge "$SIDECAR_MIN_AVAILABLE_MB" ] \
    || die "available memory ${available_mb}MB is below ${SIDECAR_MIN_AVAILABLE_MB}MB"
  disk_mb="$(df -Pk "$SIDECAR_DATA_DIR" | awk 'NR == 2 {print int($4 / 1024)}')"
  [ "$disk_mb" -ge "$SIDECAR_MIN_DISK_MB" ] \
    || die "available disk ${disk_mb}MB is below ${SIDECAR_MIN_DISK_MB}MB"
  for name in $SIDECAR_REQUIRED_CONTAINERS; do
    container_is_healthy "$name" || die "required container is not healthy: $name"
  done
}

network_json() {
  "$DOCKER_BIN" network inspect "$SIDECAR_NETWORK" 2>/dev/null
}

network_check() {
  network_json | "$PYTHON_BIN" -c '
import json,sys
name,subnet,gateway,parent=sys.argv[1:]
data=json.load(sys.stdin)[0]
configs=data.get("IPAM",{}).get("Config",[])
ok=(data.get("Driver")=="ipvlan" and data.get("Options",{}).get("parent")==parent
    and any(c.get("Subnet")==subnet and c.get("Gateway")==gateway for c in configs))
raise SystemExit(0 if ok else 1)
' "$SIDECAR_NETWORK" "$SIDECAR_SUBNET" "$SIDECAR_GATEWAY" "$SIDECAR_PARENT_IF"
}

network_ensure() {
  if "$DOCKER_BIN" network inspect "$SIDECAR_NETWORK" >/dev/null 2>&1; then
    network_check || die "existing Docker network $SIDECAR_NETWORK does not match the required ipvlan config"
    return 0
  fi
  "$DOCKER_BIN" network create --driver ipvlan --subnet "$SIDECAR_SUBNET" \
    --gateway "$SIDECAR_GATEWAY" --opt "parent=$SIDECAR_PARENT_IF" \
    --opt ipvlan_mode=l2 "$SIDECAR_NETWORK" >/dev/null
  network_check || die "created Docker network failed verification"
}

image_check() {
  "$DOCKER_BIN" image inspect "$SIDECAR_RUNTIME_IMAGE" >/dev/null 2>&1 \
    || die "runtime image is missing: $SIDECAR_RUNTIME_IMAGE"
  [ -x "$SIDECAR_ASSET_DIR/cfst" ] || die "cfst asset is missing"
  [ -s "$SIDECAR_ASSET_DIR/ip.txt" ] || die "ip.txt asset is missing"
}

docker_security_args() {
  printf '%s\n' --read-only --cap-drop ALL --security-opt no-new-privileges \
    --pids-limit "$SIDECAR_PIDS_LIMIT"
}

extract_public_ip() {
  local response="$1" ip
  ip="$(printf '%s\n' "$response" | awk -F= '$1 == "ip" {print $2; exit}')"
  if [ -n "$ip" ]; then
    printf '%s\n' "$ip"
  else
    printf '%s\n' "$response" | tr -d '[:space:]'
  fi
}

network_probe() {
  local name host_ip sidecar_ip host_response sidecar_response
  name="cfip-path-probe-$$"
  ACTIVE_CONTAINERS="$ACTIVE_CONTAINERS $name"
  host_response="$("$CURL_BIN" -fsS --connect-timeout 6 --max-time 12 "$SIDECAR_PATH_CHECK_URL")" \
    || die "host public-IP probe failed"
  host_ip="$(extract_public_ip "$host_response")"
  sidecar_response="$(
    "$DOCKER_BIN" run --rm --name "$name" --network "$SIDECAR_NETWORK" --ip "$SIDECAR_IP" \
      --cpus 0.25 --memory "$SIDECAR_CURL_MEMORY" $(docker_security_args) \
      --user 65532:65532 \
      --entrypoint /usr/bin/curl "$SIDECAR_RUNTIME_IMAGE" \
      -fsS --connect-timeout 6 --max-time 12 "$SIDECAR_PATH_CHECK_URL"
  )" || die "sidecar public-IP probe failed"
  sidecar_ip="$(extract_public_ip "$sidecar_response")"
  ACTIVE_CONTAINERS="$(printf '%s\n' "$ACTIVE_CONTAINERS" | sed "s/ $name//")"
  [ -n "$host_ip" ] && [ -n "$sidecar_ip" ] || die "public-IP probe returned an empty value"
  if [ "$SIDECAR_REQUIRE_DIFFERENT_PUBLIC_IP" = "1" ] && [ "$host_ip" = "$sidecar_ip" ]; then
    die "sidecar and proxied host expose the same public IP; direct bypass is not proven"
  fi
  log "path probe passed: host and sidecar exits are distinct"
}

qualified_count() {
  awk -F, -v min="$SIDECAR_DIRECT_MIN_MBPS" '
    NR > 1 {gsub(/\r/, "", $0); if (($6 + 0) >= min) count++}
    END {print count + 0}
  ' "$1"
}

run_direct_scan() {
  local count="$1" output="$2" name raw
  name="cfip-direct-scan-$$"
  raw="$SIDECAR_RUN_DIR/cfst-${count}.log"
  rm -f "$output" "$raw"
  ACTIVE_CONTAINERS="$ACTIVE_CONTAINERS $name"
  timeout "$SIDECAR_CFST_TOTAL_TIMEOUT" \
    "$DOCKER_BIN" run --rm --name "$name" --network "$SIDECAR_NETWORK" --ip "$SIDECAR_IP" \
      --cpus "$SIDECAR_CONTAINER_CPUS" --cpu-shares 128 --memory "$SIDECAR_SCAN_MEMORY" \
      $(docker_security_args) --user 0:0 \
      -v "$SIDECAR_ASSET_DIR/ip.txt:/app/ip.txt:ro" -v "$SIDECAR_RUN_DIR:/run/cfip:rw" \
      --entrypoint /usr/local/bin/cfst "$SIDECAR_RUNTIME_IMAGE" \
      -tp 443 -t "$SIDECAR_CFST_TIMEOUT" -n "$SIDECAR_CFST_THREADS" \
      -dn "$count" -p "$count" -tl "$SIDECAR_CFST_MAX_LATENCY" -tll "$SIDECAR_CFST_MIN_LATENCY" \
      -sl 0 -dt "$SIDECAR_CFST_DOWNLOAD_TIMEOUT" -f /app/ip.txt \
      -o /run/cfip/direct.csv -url "$SIDECAR_TEST_URL" >"$raw" 2>&1 \
    || die "direct scan failed or timed out; see $raw"
  ACTIVE_CONTAINERS="$(printf '%s\n' "$ACTIVE_CONTAINERS" | sed "s/ $name//")"
  [ -s "$SIDECAR_RUN_DIR/direct.csv" ] || die "direct scan produced no CSV"
  mv "$SIDECAR_RUN_DIR/direct.csv" "$output"
  log "direct scan completed: count=$count qualified=$(qualified_count "$output")"
}

select_candidates() {
  awk -F, -v limit="$SIDECAR_CANDIDATE_LIMIT" '
    NR > 1 && count < limit {
      gsub(/\r/, "", $0); gsub(/[[:space:]]/, "", $1)
      if ($1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) {
        printf "%s\t%.2f\n", $1, ($6 + 0); count++
      }
    }
  ' "$1"
}

start_xray() {
  local candidate="$1" config="$2" name="$3"
  "$PYTHON_BIN" "$SCRIPT_DIR/render-xray-config.py" \
    --source "$CREDENTIAL_SOURCE" --candidate "$candidate" --output "$config"
  chown root:65532 "$config"
  chmod 640 "$config"
  ACTIVE_CONTAINERS="$ACTIVE_CONTAINERS $name"
  "$DOCKER_BIN" run -d --rm --name "$name" --network "$SIDECAR_NETWORK" --ip "$SIDECAR_IP" \
    --cpus "$SIDECAR_CONTAINER_CPUS" --cpu-shares 128 --memory "$SIDECAR_XRAY_MEMORY" \
    $(docker_security_args) --user 65532:65532 --tmpfs /tmp:rw,noexec,nosuid,size=16m \
    -v "$config:/etc/xray/config.json:ro" --entrypoint /usr/local/bin/xray "$SIDECAR_RUNTIME_IMAGE" \
    run -c /etc/xray/config.json >/dev/null
  sleep 1
  [ "$("$DOCKER_BIN" inspect --format '{{.State.Running}}' "$name" 2>/dev/null || true)" = "true" ] \
    || die "Xray sidecar failed to start for $candidate"
}

stop_xray() {
  local name="$1"
  "$DOCKER_BIN" rm -f "$name" >/dev/null 2>&1 || true
  ACTIVE_CONTAINERS="$(printf '%s\n' "$ACTIVE_CONTAINERS" | sed "s/ $name//")"
}

curl_proxy_round() {
  local xray_name="$1" raw
  raw="$(
    "$DOCKER_BIN" run --rm --network "container:$xray_name" \
      --cpus 0.5 --memory "$SIDECAR_CURL_MEMORY" $(docker_security_args) \
      --user 65532:65532 --entrypoint /usr/bin/curl "$SIDECAR_RUNTIME_IMAGE" \
      -sS -L --socks5-hostname 127.0.0.1:1080 --connect-timeout 12 --max-time 70 \
      -o /dev/null -w '%{http_code}\t%{size_download}\t%{speed_download}' \
      "$SIDECAR_TEST_URL" 2>>"$SIDECAR_RUN_DIR/proxy-curl.log"
  )" || raw=$'000\t0\t0'
  printf '%s\n' "$raw"
}

validate_candidate() {
  local candidate="$1" direct_speed="$2" report="$3" name config profile_sha
  local round raw http bytes bps speed min_speed avg_speed status observed_at
  local speed1=0 speed2=0 http1=000 http2=000 bytes1=0 bytes2=0
  name="cfip-xray-$$"
  config="$SIDECAR_RUN_DIR/xray-${candidate}.json"
  profile_sha="$(sha256sum "$CREDENTIAL_SOURCE" | awk '{print $1}')"
  gate_check
  start_xray "$candidate" "$config" "$name"
  round=1
  while [ "$round" -le "$SIDECAR_PROXY_ROUNDS" ]; do
    raw="$(curl_proxy_round "$name")"
    IFS=$'\t' read -r http bytes bps <<<"$raw"
    speed="$(awk -v bps="${bps:-0}" 'BEGIN {printf "%.2f", (bps + 0) / 1048576}')"
    if [ "$round" -eq 1 ]; then http1="${http:-000}"; bytes1="${bytes:-0}"; speed1="$speed"; fi
    if [ "$round" -eq 2 ]; then http2="${http:-000}"; bytes2="${bytes:-0}"; speed2="$speed"; fi
    round=$((round + 1))
  done
  stop_xray "$name"
  rm -f "$config"
  min_speed="$(awk -v a="$speed1" -v b="$speed2" 'BEGIN {printf "%.2f", a < b ? a : b}')"
  avg_speed="$(awk -v a="$speed1" -v b="$speed2" 'BEGIN {printf "%.2f", (a + b) / 2}')"
  status="low"
  if [ "$http1" = "200" ] && [ "$http2" = "200" ] \
    && [ "$bytes1" -ge "$SIDECAR_PROXY_MIN_BYTES" ] && [ "$bytes2" -ge "$SIDECAR_PROXY_MIN_BYTES" ] \
    && awk -v speed="$min_speed" -v min="$SIDECAR_PROXY_MIN_MBPS" 'BEGIN {exit speed >= min ? 0 : 1}'; then
    status="pass"
  fi
  observed_at="$(date '+%F %T')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$observed_at" "$candidate" "$direct_speed" "$speed1" "$speed2" "$min_speed" "$avg_speed" \
    "$http1" "$http2" "$status" "$profile_sha" "sidecar_proxy" >>"$report"
  log "proxy validation: candidate=$candidate min=${min_speed}MB/s avg=${avg_speed}MB/s status=$status"
}

observe() {
  local run_id report direct candidates count qualified candidate direct_speed
  acquire_lock
  need_cmd "$DOCKER_BIN"; need_cmd "$CURL_BIN"; need_cmd "$PYTHON_BIN"; need_cmd flock; need_cmd timeout
  gate_check
  network_check || die "sidecar ipvlan network is missing or invalid"
  image_check
  [ -r "$CREDENTIAL_SOURCE" ] || die "encrypted systemd credential was not loaded"
  [ "$SIDECAR_PROXY_ROUNDS" -eq 2 ] || die "this deployment requires exactly two proxy rounds"
  network_probe
  run_id="$(date '+%Y%m%d-%H%M%S')"
  report="$SIDECAR_DATA_DIR/observations/sidecar-observation-$run_id.tsv"
  direct="$SIDECAR_DATA_DIR/observations/direct-$run_id.csv"
  printf 'observed_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tprofile_sha256\tpath_mode\n' >"$report"
  count="$SIDECAR_DIRECT_INITIAL_COUNT"
  run_direct_scan "$count" "$direct"
  qualified="$(qualified_count "$direct")"
  if [ "$qualified" -lt "$SIDECAR_DIRECT_REQUIRED" ] && [ "$count" -lt "$SIDECAR_DIRECT_MAX_COUNT" ]; then
    gate_check
    count=$((count + SIDECAR_DIRECT_STEP))
    [ "$count" -le "$SIDECAR_DIRECT_MAX_COUNT" ] || count="$SIDECAR_DIRECT_MAX_COUNT"
    run_direct_scan "$count" "$direct"
  fi
  candidates="$SIDECAR_RUN_DIR/candidates.tsv"
  select_candidates "$direct" >"$candidates"
  [ -s "$candidates" ] || die "direct scan produced no candidates"
  while IFS=$'\t' read -r candidate direct_speed; do
    validate_candidate "$candidate" "$direct_speed" "$report"
  done <"$candidates"
  cp "$report" "$SIDECAR_DATA_DIR/sidecar-observation.latest.tsv"
  cp "$direct" "$SIDECAR_DATA_DIR/direct.latest.csv"
  find "$SIDECAR_DATA_DIR/observations" -type f -mtime +30 -delete 2>/dev/null || true
  log "observation complete: report=$report; no DNS or champion-pool update was attempted"
}

canary() {
  local candidate="${1:-}" report
  [ -n "$candidate" ] || die "canary requires one IPv4 candidate"
  acquire_lock
  need_cmd "$DOCKER_BIN"; need_cmd "$CURL_BIN"; need_cmd "$PYTHON_BIN"; need_cmd flock
  gate_check
  network_check || die "sidecar ipvlan network is missing or invalid"
  image_check
  [ -r "$CREDENTIAL_SOURCE" ] || die "encrypted systemd credential was not loaded"
  [ "$SIDECAR_PROXY_ROUNDS" -eq 2 ] || die "this deployment requires exactly two proxy rounds"
  network_probe
  report="$SIDECAR_DATA_DIR/sidecar-canary.latest.tsv"
  printf 'observed_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tprofile_sha256\tpath_mode\n' >"$report"
  validate_candidate "$candidate" "not_measured" "$report"
  log "canary complete: report=$report; no direct scan, DNS update, or pool update was attempted"
}

status() {
  prepare_dirs
  printf 'network='; if network_check >/dev/null 2>&1; then echo ok; else echo missing_or_invalid; fi
  printf 'image='; if "$DOCKER_BIN" image inspect "$SIDECAR_RUNTIME_IMAGE" >/dev/null 2>&1; then echo ok; else echo missing; fi
  printf 'timer='; systemctl is-enabled cfip-sidecar.timer 2>/dev/null || true
  printf 'service='; systemctl is-active cfip-sidecar.service 2>/dev/null || true
  printf 'latest_report='; [ -s "$SIDECAR_DATA_DIR/sidecar-observation.latest.tsv" ] && echo present || echo absent
}

case "${1:-}" in
  preflight) acquire_lock; gate_check; network_check; image_check; echo "preflight=ok" ;;
  network-ensure) acquire_lock; network_ensure; echo "network=ok" ;;
  path-check) acquire_lock; gate_check; network_check; image_check; network_probe ;;
  canary) canary "${2:-}" ;;
  observe) observe ;;
  status) status ;;
  *) echo "Usage: $0 {preflight|network-ensure|path-check|canary IPv4|observe|status}" >&2; exit 2 ;;
esac
