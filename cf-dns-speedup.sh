#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="${CONFIG_FILE:-$APP_DIR/config.env}"
CFST_BIN="${CFST_BIN:-$APP_DIR/cfst}"
IP_FILE="${IP_FILE:-$APP_DIR/ip.txt}"
RESULT_FILE="${RESULT_FILE:-$APP_DIR/result.csv}"
STABILITY_RESULT_FILE="${STABILITY_RESULT_FILE:-$APP_DIR/result.stability.tsv}"
STABILITY_VERIFY_RESULT_FILE="${STABILITY_VERIFY_RESULT_FILE:-$APP_DIR/result.stability.verify.tsv}"
HEALTH_REPORT_FILE="${HEALTH_REPORT_FILE:-$APP_DIR/health-check.latest.txt}"
VALIDATE_RESULT_FILE="${VALIDATE_RESULT_FILE:-$APP_DIR/validate-current.latest.tsv}"
OBSERVATION_HISTORY_FILE="${OBSERVATION_HISTORY_FILE:-$APP_DIR/observation-history.tsv}"
CURRENT_OBSERVATION_REPORT_FILE="${CURRENT_OBSERVATION_REPORT_FILE:-$APP_DIR/current-observation-report.latest.txt}"
CHAMPION_POOL_FILE="${CHAMPION_POOL_FILE:-$APP_DIR/champion-pool.tsv}"
CHAMPION_LIFECYCLE_AUDIT_FILE="${CHAMPION_LIFECYCLE_AUDIT_FILE:-$APP_DIR/champion-lifecycle-audit.tsv}"
CHAMPION_REPORT_FILE="${CHAMPION_REPORT_FILE:-$APP_DIR/champion-report.latest.txt}"
EXTERNAL_OBSERVATION_POOL_FILE="${EXTERNAL_OBSERVATION_POOL_FILE:-$APP_DIR/external-observation-pool.tsv}"
EXTERNAL_CANDIDATE_CHECK_FILE="${EXTERNAL_CANDIDATE_CHECK_FILE:-$APP_DIR/external-candidates.check.txt}"
EXTERNAL_CANDIDATE_REPORT_FILE="${EXTERNAL_CANDIDATE_REPORT_FILE:-$APP_DIR/external-candidates.report.txt}"
EXTERNAL_RUNTIME_IP_FILE=""
LOG_FILE="${LOG_FILE:-$APP_DIR/run.log}"
INFORM_LOG="${INFORM_LOG:-$APP_DIR/informlog}"
CFST_RAW_LOG="${CFST_RAW_LOG:-$APP_DIR/cfst-output.log}"
LOCK_DIR="${LOCK_DIR:-/tmp/cf-dns-speedup.lock}"
LAST_RUN_SUMMARY="${LAST_RUN_SUMMARY:-$APP_DIR/last-run.summary}"
LAST_RUN_JSON="${LAST_RUN_JSON:-$APP_DIR/last-run.json}"
LOG_MAX_KB="${LOG_MAX_KB:-1024}"
LOG_KEEP_DAYS="${LOG_KEEP_DAYS:-14}"

CFST_SOURCE_BASE="${CFST_SOURCE_BASE:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3}"
DEFAULT_IPV4_LIST="${DEFAULT_IPV4_LIST:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3/ip.txt}"
DEFAULT_IPV6_LIST="${DEFAULT_IPV6_LIST:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3/ipv6.txt}"
REVERSE_ZIP_PRIMARY="${REVERSE_ZIP_PRIMARY:-https://zip.baipiao.eu.org}"
REVERSE_ZIP_FALLBACK="${REVERSE_ZIP_FALLBACK:-https://cf.yg-kkk.gq}"

PROXY_STOPPED=0
PROXY_SERVICE=""
LOCK_ACQUIRED=0
RUN_STATUS="not-started"
RUN_STARTED_AT=""
RUN_FINISHED_AT=""
RUN_ERROR=""

log() {
  mkdir -p "$APP_DIR"
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

inform() {
  mkdir -p "$APP_DIR"
  printf '%s\n' "$*" | tee -a "$INFORM_LOG"
}

die() {
  RUN_STATUS="failed"
  RUN_ERROR="$*"
  log "错误：$*"
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"
}

load_config() {
  [ -f "$CONFIG_FILE" ] || die "配置文件不存在：$CONFIG_FILE"
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"

  PUSH_MODE="${PUSH_MODE:-domain}"
  DOMAIN_UPDATE_MODE="${DOMAIN_UPDATE_MODE:-multi}"
  CDN_IP_MODE="${CDN_IP_MODE:-official}"
  CF_API_TOKEN="${CF_API_TOKEN:-}"
  CF_ZONE_ID="${CF_ZONE_ID:-}"
  CF_RECORD_NAME="${CF_RECORD_NAME:-}"
  CF_RECORD_NAMES="${CF_RECORD_NAMES:-}"
  CF_PROXIED="${CF_PROXIED:-false}"
  CF_TTL="${CF_TTL:-60}"
  CFST_PORT="${CFST_PORT:-443}"
  CFST_THREADS="${CFST_THREADS:-32}"
  CFST_COUNT="${CFST_COUNT:-5}"
  CFST_DOWNLOAD_COUNT="${CFST_DOWNLOAD_COUNT:-$CFST_COUNT}"
  CFST_DOWNLOAD_COUNT_STEP="${CFST_DOWNLOAD_COUNT_STEP:-0}"
  CFST_DOWNLOAD_COUNT_MAX="${CFST_DOWNLOAD_COUNT_MAX:-$CFST_DOWNLOAD_COUNT}"
  CFST_RESULT_COUNT="${CFST_RESULT_COUNT:-$CFST_COUNT}"
  CFST_TIMEOUT="${CFST_TIMEOUT:-4}"
  CFST_TOTAL_TIMEOUT="${CFST_TOTAL_TIMEOUT:-900}"
  CFST_DOWNLOAD_TIMEOUT="${CFST_DOWNLOAD_TIMEOUT:-8}"
  CFST_MIN_SPEED="${CFST_MIN_SPEED:-0}"
  CFST_PREFER_MIN_SPEED="${CFST_PREFER_MIN_SPEED:-0}"
  CFST_STABILITY_TEST_COUNT="${CFST_STABILITY_TEST_COUNT:-0}"
  CFST_STABILITY_TEST_ROUNDS="${CFST_STABILITY_TEST_ROUNDS:-0}"
  CFST_STABILITY_CONNECT_TIMEOUT="${CFST_STABILITY_CONNECT_TIMEOUT:-6}"
  CFST_STABILITY_TIMEOUT="${CFST_STABILITY_TIMEOUT:-35}"
  VALIDATE_CURRENT_ROUNDS="${VALIDATE_CURRENT_ROUNDS:-2}"
  CFST_OBSERVE_CRON="${CFST_OBSERVE_CRON:-30 14,20 * * *}"
  CFST_OBSERVE_MIN_SPEED="${CFST_OBSERVE_MIN_SPEED:-$CFST_RETAIN_MIN_SPEED}"
  CFST_PRIMARY_SAFE_MODE="${CFST_PRIMARY_SAFE_MODE:-1}"
  CFST_PRIMARY_MIN_SPEED="${CFST_PRIMARY_MIN_SPEED:-$CFST_RETAIN_MIN_SPEED}"
  CFST_PRIMARY_FALLBACK_MIN_SPEED="${CFST_PRIMARY_FALLBACK_MIN_SPEED:-6.5}"
  CFST_PRIMARY_PREFER_REGEX="${CFST_PRIMARY_PREFER_REGEX:-^104\\.17\\.}"
  CFST_PRIMARY_AVOID_REGEX="${CFST_PRIMARY_AVOID_REGEX:-^(104\\.20\\.|104\\.26\\.|172\\.67\\.)}"
  CFST_PRIMARY_ALLOW_CHALLENGER="${CFST_PRIMARY_ALLOW_CHALLENGER:-0}"
  CFST_STABLE_SLOT_MODE="${CFST_STABLE_SLOT_MODE:-1}"
  CFST_STABLE_SLOT_COUNT="${CFST_STABLE_SLOT_COUNT:-3}"
  CFST_STABLE_SLOT_MIN_SPEED="${CFST_STABLE_SLOT_MIN_SPEED:-$CFST_PRIMARY_MIN_SPEED}"
  CFST_STABLE_SLOT_FALLBACK_MIN_SPEED="${CFST_STABLE_SLOT_FALLBACK_MIN_SPEED:-$CFST_PRIMARY_FALLBACK_MIN_SPEED}"
  CFST_STABLE_SLOT_PREFER_REGEX="${CFST_STABLE_SLOT_PREFER_REGEX:-$CFST_PRIMARY_PREFER_REGEX}"
  CFST_STABLE_SLOT_AVOID_REGEX="${CFST_STABLE_SLOT_AVOID_REGEX:-$CFST_PRIMARY_AVOID_REGEX}"
  CFST_STABLE_SLOT_ALLOW_CHALLENGER="${CFST_STABLE_SLOT_ALLOW_CHALLENGER:-0}"
  CFST_STABLE_SLOT_ALLOW_AVOID="${CFST_STABLE_SLOT_ALLOW_AVOID:-0}"
  CFST_OBSERVATION_CANDIDATES="${CFST_OBSERVATION_CANDIDATES:-1}"
  CFST_OBSERVATION_CANDIDATE_MIN_SPEED="${CFST_OBSERVATION_CANDIDATE_MIN_SPEED:-$CFST_STABLE_SLOT_MIN_SPEED}"
  CFST_DUAL_POOL_MODE="${CFST_DUAL_POOL_MODE:-1}"
  CFST_COMPETITIVE_SLOT_COUNT="${CFST_COMPETITIVE_SLOT_COUNT:-2}"
  CFST_OBSERVATION_RECENT_WINDOW="${CFST_OBSERVATION_RECENT_WINDOW:-2}"
  CFST_OBSERVATION_STALE_LOW_COUNT="${CFST_OBSERVATION_STALE_LOW_COUNT:-3}"
  CFST_OBSERVATION_STABLE_MAX_LOW_COUNT="${CFST_OBSERVATION_STABLE_MAX_LOW_COUNT:-1}"
  CFST_COMPARE_CURRENT_DNS="${CFST_COMPARE_CURRENT_DNS:-1}"
  CFST_CHAMPION_POOL="${CFST_CHAMPION_POOL:-1}"
  CFST_CHAMPION_POOL_SIZE="${CFST_CHAMPION_POOL_SIZE:-10}"
  CFST_RETAIN_RATIO="${CFST_RETAIN_RATIO:-0.90}"
  CFST_REPLACE_IMPROVE_RATIO="${CFST_REPLACE_IMPROVE_RATIO:-1.25}"
  CFST_DEGRADE_MIN_SPEED="${CFST_DEGRADE_MIN_SPEED:-2}"
  CFST_RETAIN_MIN_SPEED="${CFST_RETAIN_MIN_SPEED:-8}"
  CFST_CHAMPION_FAIL_MIN_SPEED="${CFST_CHAMPION_FAIL_MIN_SPEED:-$CFST_RETAIN_MIN_SPEED}"
  CFST_FAIL_EVICT_COUNT="${CFST_FAIL_EVICT_COUNT:-3}"
  CFST_FINAL_CANDIDATE_LIMIT="${CFST_FINAL_CANDIDATE_LIMIT:-30}"
  CFST_EXTERNAL_CANDIDATES="${CFST_EXTERNAL_CANDIDATES:-0}"
  CFST_EXTERNAL_CANDIDATE_URLS="${CFST_EXTERNAL_CANDIDATE_URLS:-}"
  CFST_EXTERNAL_CANDIDATE_LIMIT="${CFST_EXTERNAL_CANDIDATE_LIMIT:-5000}"
  CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT="${CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT:-2000}"
  CFST_EXTERNAL_CANDIDATE_URL_LIMIT="${CFST_EXTERNAL_CANDIDATE_URL_LIMIT:-5}"
  CFST_EXTERNAL_CANDIDATE_MAX_BYTES="${CFST_EXTERNAL_CANDIDATE_MAX_BYTES:-1048576}"
  CFST_EXTERNAL_CANDIDATE_MAX_LINES="${CFST_EXTERNAL_CANDIDATE_MAX_LINES:-20000}"
  CFST_EXTERNAL_CANDIDATE_ALLOWED_HOSTS="${CFST_EXTERNAL_CANDIDATE_ALLOWED_HOSTS:-raw.githubusercontent.com}"
  CFST_EXTERNAL_CANDIDATE_MODE="${CFST_EXTERNAL_CANDIDATE_MODE:-append}"
  CFST_EXTERNAL_CANDIDATES_ALLOW_DNS="${CFST_EXTERNAL_CANDIDATES_ALLOW_DNS:-0}"
  CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION="${CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION:-0}"
  CFST_EXTERNAL_OBSERVATION_POOL="${CFST_EXTERNAL_OBSERVATION_POOL:-1}"
  CFST_EXTERNAL_PROMOTION_ROUNDS="${CFST_EXTERNAL_PROMOTION_ROUNDS:-3}"
  CFST_EXTERNAL_PROMOTION_MIN_SPEED="${CFST_EXTERNAL_PROMOTION_MIN_SPEED:-0}"
  CFST_EXTERNAL_OBSERVATION_EVICT_FAILS="${CFST_EXTERNAL_OBSERVATION_EVICT_FAILS:-3}"
  CFST_ISP_PROFILE="${CFST_ISP_PROFILE:-}"
  normalize_retention_config
  normalize_slot_config
  normalize_external_candidate_config
  CFST_MAX_LATENCY="${CFST_MAX_LATENCY:-9999}"
  CFST_MIN_LATENCY="${CFST_MIN_LATENCY:-0}"
  CFST_URL="${CFST_URL:-}"
  IP_VERSION="${IP_VERSION:-ipv4}"
  DRY_RUN="${DRY_RUN_OVERRIDE:-${DRY_RUN:-1}}"
  enforce_external_candidate_safety
  PROXY_PLUGIN="${PROXY_PLUGIN:-0}"
  PROXY_RESTART_WAIT="${PROXY_RESTART_WAIT:-30}"
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  TELEGRAM_USER_ID="${TELEGRAM_USER_ID:-}"
  TELEGRAM_API="${TELEGRAM_API:-api.telegram.org}"
  PUSHPLUS_TOKEN="${PUSHPLUS_TOKEN:-}"
  LOG_MAX_KB="${LOG_MAX_KB:-1024}"
  LOG_KEEP_DAYS="${LOG_KEEP_DAYS:-14}"
}

normalize_retention_config() {
  CFST_CHAMPION_POOL_SIZE="$(awk -v v="$CFST_CHAMPION_POOL_SIZE" 'BEGIN {v+=0; if (v < 1) v=10; print int(v)}')"
  CFST_FAIL_EVICT_COUNT="$(awk -v v="$CFST_FAIL_EVICT_COUNT" 'BEGIN {v+=0; if (v < 1) v=3; print int(v)}')"
  CFST_FINAL_CANDIDATE_LIMIT="$(awk -v v="$CFST_FINAL_CANDIDATE_LIMIT" 'BEGIN {v+=0; if (v < 1) v=30; print int(v)}')"
  CFST_RETAIN_RATIO="$(awk -v v="$CFST_RETAIN_RATIO" 'BEGIN {v+=0; if (v <= 0 || v > 1) v=0.90; printf "%.2f", v}')"
  CFST_REPLACE_IMPROVE_RATIO="$(awk -v v="$CFST_REPLACE_IMPROVE_RATIO" 'BEGIN {v+=0; if (v < 1) v=1.25; printf "%.2f", v}')"
  CFST_DEGRADE_MIN_SPEED="$(awk -v v="$CFST_DEGRADE_MIN_SPEED" 'BEGIN {v+=0; if (v < 0) v=2; printf "%.2f", v}')"
  CFST_RETAIN_MIN_SPEED="$(awk -v v="$CFST_RETAIN_MIN_SPEED" 'BEGIN {v+=0; if (v < 0) v=8; printf "%.2f", v}')"
  CFST_CHAMPION_FAIL_MIN_SPEED="$(awk -v v="$CFST_CHAMPION_FAIL_MIN_SPEED" -v fallback="$CFST_RETAIN_MIN_SPEED" 'BEGIN {v+=0; fallback+=0; if (v < 0) v=fallback; printf "%.2f", v}')"
  CFST_PRIMARY_MIN_SPEED="$(awk -v v="$CFST_PRIMARY_MIN_SPEED" -v fallback="$CFST_RETAIN_MIN_SPEED" 'BEGIN {v+=0; fallback+=0; if (v < 0) v=fallback; printf "%.2f", v}')"
  CFST_PRIMARY_FALLBACK_MIN_SPEED="$(awk -v v="$CFST_PRIMARY_FALLBACK_MIN_SPEED" -v fallback="$CFST_PRIMARY_MIN_SPEED" 'BEGIN {v+=0; fallback+=0; if (v <= 0 || v > fallback) v=fallback; printf "%.2f", v}')"
}

normalize_slot_config() {
  CFST_STABLE_SLOT_COUNT="$(awk -v v="$CFST_STABLE_SLOT_COUNT" -v limit="$CFST_RESULT_COUNT" 'BEGIN {v+=0; limit+=0; if (v < 0) v=0; if (limit > 0 && v > limit) v=limit; print int(v)}')"
  CFST_STABLE_SLOT_MIN_SPEED="$(awk -v v="$CFST_STABLE_SLOT_MIN_SPEED" -v fallback="$CFST_RETAIN_MIN_SPEED" 'BEGIN {v+=0; fallback+=0; if (v <= 0) v=fallback; printf "%.2f", v}')"
  CFST_STABLE_SLOT_FALLBACK_MIN_SPEED="$(awk -v v="$CFST_STABLE_SLOT_FALLBACK_MIN_SPEED" -v fallback="$CFST_STABLE_SLOT_MIN_SPEED" 'BEGIN {v+=0; fallback+=0; if (v <= 0 || v > fallback) v=fallback; printf "%.2f", v}')"
  CFST_OBSERVATION_CANDIDATE_MIN_SPEED="$(awk -v v="$CFST_OBSERVATION_CANDIDATE_MIN_SPEED" -v fallback="$CFST_STABLE_SLOT_MIN_SPEED" 'BEGIN {v+=0; fallback+=0; if (v <= 0) v=fallback; printf "%.2f", v}')"
  CFST_COMPETITIVE_SLOT_COUNT="$(awk -v v="$CFST_COMPETITIVE_SLOT_COUNT" -v limit="$CFST_RESULT_COUNT" 'BEGIN {v+=0; limit+=0; if (v < 0) v=0; if (limit > 0 && v > limit) v=limit; print int(v)}')"
  CFST_OBSERVATION_RECENT_WINDOW="$(awk -v v="$CFST_OBSERVATION_RECENT_WINDOW" 'BEGIN {v+=0; if (v < 1) v=2; print int(v)}')"
  CFST_OBSERVATION_STALE_LOW_COUNT="$(awk -v v="$CFST_OBSERVATION_STALE_LOW_COUNT" 'BEGIN {v+=0; if (v < 1) v=3; print int(v)}')"
  CFST_OBSERVATION_STABLE_MAX_LOW_COUNT="$(awk -v v="$CFST_OBSERVATION_STABLE_MAX_LOW_COUNT" 'BEGIN {v+=0; if (v < 0) v=1; print int(v)}')"
}

normalize_external_candidate_config() {
  CFST_EXTERNAL_CANDIDATE_LIMIT="$(awk -v v="$CFST_EXTERNAL_CANDIDATE_LIMIT" 'BEGIN {v+=0; if (v < 1) v=5000; print int(v)}')"
  CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT="$(awk -v v="$CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT" 'BEGIN {v+=0; if (v < 1) v=2000; print int(v)}')"
  CFST_EXTERNAL_CANDIDATE_URL_LIMIT="$(awk -v v="$CFST_EXTERNAL_CANDIDATE_URL_LIMIT" 'BEGIN {v+=0; if (v < 1) v=5; if (v > 20) v=20; print int(v)}')"
  CFST_EXTERNAL_CANDIDATE_MAX_BYTES="$(awk -v v="$CFST_EXTERNAL_CANDIDATE_MAX_BYTES" 'BEGIN {v+=0; if (v < 1024) v=1048576; print int(v)}')"
  CFST_EXTERNAL_CANDIDATE_MAX_LINES="$(awk -v v="$CFST_EXTERNAL_CANDIDATE_MAX_LINES" 'BEGIN {v+=0; if (v < 1) v=20000; print int(v)}')"
  CFST_EXTERNAL_PROMOTION_ROUNDS="$(awk -v v="$CFST_EXTERNAL_PROMOTION_ROUNDS" 'BEGIN {v+=0; if (v < 1) v=3; print int(v)}')"
  CFST_EXTERNAL_PROMOTION_MIN_SPEED="$(awk -v v="$CFST_EXTERNAL_PROMOTION_MIN_SPEED" 'BEGIN {v+=0; if (v < 0) v=0; printf "%.2f", v}')"
  CFST_EXTERNAL_OBSERVATION_EVICT_FAILS="$(awk -v v="$CFST_EXTERNAL_OBSERVATION_EVICT_FAILS" 'BEGIN {v+=0; if (v < 1) v=3; print int(v)}')"
  case "$CFST_EXTERNAL_CANDIDATE_MODE" in
    append) ;;
    *) CFST_EXTERNAL_CANDIDATE_MODE="append" ;;
  esac
  case "$CFST_ISP_PROFILE" in
    ""|cmcc|cu|ct|cf) ;;
    *) die "CFST_ISP_PROFILE 仅支持空值、cmcc、cu、ct、cf" ;;
  esac
}

enforce_external_candidate_safety() {
  [ "${CFST_EXTERNAL_CANDIDATES:-0}" = "1" ] || return 0
  if [ "${CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION:-0}" != "1" ]; then
    CFST_CHAMPION_POOL=0
  fi
}

rotate_file_if_needed() {
  local path="$1"
  [ -f "$path" ] || return 0
  [ "${LOG_MAX_KB:-0}" -gt 0 ] 2>/dev/null || return 0
  local size_kb
  size_kb="$(du -k "$path" 2>/dev/null | awk '{print $1}')"
  [ -n "$size_kb" ] || return 0
  if [ "$size_kb" -gt "$LOG_MAX_KB" ]; then
    local rotated="${path}.$(date '+%Y%m%d-%H%M%S')"
    mv "$path" "$rotated"
    gzip -f "$rotated" 2>/dev/null || true
    : > "$path"
  fi
}

prune_old_logs() {
  [ "${LOG_KEEP_DAYS:-0}" -gt 0 ] 2>/dev/null || return 0
  find "$APP_DIR" -maxdepth 1 -type f \( -name 'run.log.*.gz' -o -name 'cfst-output.log.*.gz' \) -mtime "+$LOG_KEEP_DAYS" -delete 2>/dev/null || true
}

rotate_logs() {
  mkdir -p "$APP_DIR"
  rotate_file_if_needed "$LOG_FILE"
  rotate_file_if_needed "$CFST_RAW_LOG"
  prune_old_logs
}

acquire_lock() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_ACQUIRED=1
    printf '%s\n' "$$" > "$LOCK_DIR/pid"
    printf '%s\n' "$(date '+%F %T')" > "$LOCK_DIR/started_at"
    return 0
  fi

  local pid=""
  [ -f "$LOCK_DIR/pid" ] && pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    log "已有任务正在运行：pid=$pid，退出以避免重复执行"
    exit 0
  fi

  log "检测到陈旧锁：$LOCK_DIR，清理后重新加锁"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR" || die "无法创建锁目录：$LOCK_DIR"
  LOCK_ACQUIRED=1
  printf '%s\n' "$$" > "$LOCK_DIR/pid"
  printf '%s\n' "$(date '+%F %T')" > "$LOCK_DIR/started_at"
}

release_lock() {
  if [ "$LOCK_ACQUIRED" = "1" ]; then
    rm -rf "$LOCK_DIR"
    LOCK_ACQUIRED=0
  fi
}

json_escape() {
  jq -Rsa . 2>/dev/null || sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'
}

file_mtime() {
  [ -f "$1" ] || return 0
  date -r "$1" '+%F %T' 2>/dev/null || stat -c '%y' "$1" 2>/dev/null | cut -d. -f1 || true
}

write_run_summary() {
  RUN_FINISHED_AT="$(date '+%F %T')"
  local best_ips=""
  local stability_updated_at=""
  if [ -s "$RESULT_FILE" ]; then
    best_ips="$(best_ip_list | awk '{if (out != "") out = out " "; out = out $1} END {print out}')"
  fi
  stability_updated_at="$(file_mtime "$STABILITY_RESULT_FILE")"

  {
    echo "status=$RUN_STATUS"
    echo "started_at=$RUN_STARTED_AT"
    echo "finished_at=$RUN_FINISHED_AT"
    echo "mode=$PUSH_MODE"
    echo "domain_update_mode=$DOMAIN_UPDATE_MODE"
    echo "cdn_ip_mode=$CDN_IP_MODE"
    echo "cfst_download_count=$CFST_DOWNLOAD_COUNT"
    echo "cfst_download_count_step=$CFST_DOWNLOAD_COUNT_STEP"
    echo "cfst_download_count_max=$CFST_DOWNLOAD_COUNT_MAX"
    echo "cfst_result_count=$CFST_RESULT_COUNT"
    echo "cfst_prefer_min_speed=$CFST_PREFER_MIN_SPEED"
    echo "cfst_stability_test_count=$CFST_STABILITY_TEST_COUNT"
    echo "cfst_stability_test_rounds=$CFST_STABILITY_TEST_ROUNDS"
    echo "cfst_stable_slot_mode=$CFST_STABLE_SLOT_MODE"
    echo "cfst_stable_slot_count=$CFST_STABLE_SLOT_COUNT"
    echo "cfst_stable_slot_min_speed=$CFST_STABLE_SLOT_MIN_SPEED"
    echo "cfst_stable_slot_fallback_min_speed=$CFST_STABLE_SLOT_FALLBACK_MIN_SPEED"
    echo "cfst_stable_slot_allow_challenger=$CFST_STABLE_SLOT_ALLOW_CHALLENGER"
    echo "cfst_stable_slot_allow_avoid=$CFST_STABLE_SLOT_ALLOW_AVOID"
    echo "cfst_observation_candidates=$CFST_OBSERVATION_CANDIDATES"
    echo "cfst_observation_candidate_min_speed=$CFST_OBSERVATION_CANDIDATE_MIN_SPEED"
    echo "cfst_dual_pool_mode=$CFST_DUAL_POOL_MODE"
    echo "cfst_competitive_slot_count=$CFST_COMPETITIVE_SLOT_COUNT"
    echo "cfst_observation_stale_low_count=$CFST_OBSERVATION_STALE_LOW_COUNT"
    echo "stability_result_file=$STABILITY_RESULT_FILE"
    echo "stability_result_updated_at=$stability_updated_at"
    echo "dry_run=$DRY_RUN"
    echo "proxy_service=$PROXY_SERVICE"
    echo "best_ips=$best_ips"
    echo "error=$RUN_ERROR"
  } > "$LAST_RUN_SUMMARY"

  {
    printf '{\n'
    printf '  "status": %s,\n' "$(printf '%s' "$RUN_STATUS" | json_escape)"
    printf '  "started_at": %s,\n' "$(printf '%s' "$RUN_STARTED_AT" | json_escape)"
    printf '  "finished_at": %s,\n' "$(printf '%s' "$RUN_FINISHED_AT" | json_escape)"
    printf '  "mode": %s,\n' "$(printf '%s' "$PUSH_MODE" | json_escape)"
    printf '  "domain_update_mode": %s,\n' "$(printf '%s' "$DOMAIN_UPDATE_MODE" | json_escape)"
    printf '  "cdn_ip_mode": %s,\n' "$(printf '%s' "$CDN_IP_MODE" | json_escape)"
    printf '  "cfst_download_count": %s,\n' "$(printf '%s' "$CFST_DOWNLOAD_COUNT" | json_escape)"
    printf '  "cfst_download_count_step": %s,\n' "$(printf '%s' "$CFST_DOWNLOAD_COUNT_STEP" | json_escape)"
    printf '  "cfst_download_count_max": %s,\n' "$(printf '%s' "$CFST_DOWNLOAD_COUNT_MAX" | json_escape)"
    printf '  "cfst_result_count": %s,\n' "$(printf '%s' "$CFST_RESULT_COUNT" | json_escape)"
    printf '  "cfst_prefer_min_speed": %s,\n' "$(printf '%s' "$CFST_PREFER_MIN_SPEED" | json_escape)"
    printf '  "cfst_stability_test_count": %s,\n' "$(printf '%s' "$CFST_STABILITY_TEST_COUNT" | json_escape)"
    printf '  "cfst_stability_test_rounds": %s,\n' "$(printf '%s' "$CFST_STABILITY_TEST_ROUNDS" | json_escape)"
    printf '  "cfst_stable_slot_mode": %s,\n' "$(printf '%s' "$CFST_STABLE_SLOT_MODE" | json_escape)"
    printf '  "cfst_stable_slot_count": %s,\n' "$(printf '%s' "$CFST_STABLE_SLOT_COUNT" | json_escape)"
    printf '  "cfst_stable_slot_min_speed": %s,\n' "$(printf '%s' "$CFST_STABLE_SLOT_MIN_SPEED" | json_escape)"
    printf '  "cfst_stable_slot_fallback_min_speed": %s,\n' "$(printf '%s' "$CFST_STABLE_SLOT_FALLBACK_MIN_SPEED" | json_escape)"
    printf '  "cfst_stable_slot_allow_challenger": %s,\n' "$(printf '%s' "$CFST_STABLE_SLOT_ALLOW_CHALLENGER" | json_escape)"
    printf '  "cfst_stable_slot_allow_avoid": %s,\n' "$(printf '%s' "$CFST_STABLE_SLOT_ALLOW_AVOID" | json_escape)"
    printf '  "cfst_observation_candidates": %s,\n' "$(printf '%s' "$CFST_OBSERVATION_CANDIDATES" | json_escape)"
    printf '  "cfst_observation_candidate_min_speed": %s,\n' "$(printf '%s' "$CFST_OBSERVATION_CANDIDATE_MIN_SPEED" | json_escape)"
    printf '  "cfst_dual_pool_mode": %s,\n' "$(printf '%s' "$CFST_DUAL_POOL_MODE" | json_escape)"
    printf '  "cfst_competitive_slot_count": %s,\n' "$(printf '%s' "$CFST_COMPETITIVE_SLOT_COUNT" | json_escape)"
    printf '  "cfst_observation_stale_low_count": %s,\n' "$(printf '%s' "$CFST_OBSERVATION_STALE_LOW_COUNT" | json_escape)"
    printf '  "stability_result_file": %s,\n' "$(printf '%s' "$STABILITY_RESULT_FILE" | json_escape)"
    printf '  "stability_result_updated_at": %s,\n' "$(printf '%s' "$stability_updated_at" | json_escape)"
    printf '  "dry_run": %s,\n' "$(printf '%s' "$DRY_RUN" | json_escape)"
    printf '  "proxy_service": %s,\n' "$(printf '%s' "$PROXY_SERVICE" | json_escape)"
    printf '  "best_ips": %s,\n' "$(printf '%s' "$best_ips" | json_escape)"
    printf '  "error": %s\n' "$(printf '%s' "$RUN_ERROR" | json_escape)"
    printf '}\n'
  } > "$LAST_RUN_JSON"
}

require_cloudflare_config() {
  [ -n "$CF_API_TOKEN" ] || die "未配置 Cloudflare API Token"
  [ -n "$CF_ZONE_ID" ] || die "未配置 Cloudflare Zone ID"
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
    *) die "暂不支持当前架构：$(uname -m)" ;;
  esac
}

install_deps_openwrt() {
  local missing=""
  for cmd in curl jq timeout unzip awk sed; do
    command -v "$cmd" >/dev/null 2>&1 || missing="$missing $cmd"
  done
  if [ -n "$missing" ] && grep -qi openwrt /etc/os-release 2>/dev/null; then
    log "检测到缺少依赖：$missing，开始安装 OpenWrt 依赖"
    opkg update
    opkg install curl jq coreutils-timeout unzip ca-bundle ca-certificates gawk sed
  fi
}

download_if_missing() {
  local url="$1"
  local path="$2"
  [ -s "$path" ] && return 0
  log "下载：$url"
  curl -fL --connect-timeout 10 --max-time 180 --retry 2 --retry-delay 2 -o "$path" "$url"
}

prepare_cfst() {
  local arch
  arch="$(detect_arch)"
  download_if_missing "$CFST_SOURCE_BASE/$arch" "$CFST_BIN"
  chmod +x "$CFST_BIN"
}

prepare_official_ip_list() {
  if [ "$IP_VERSION" = "ipv6" ]; then
    log "准备 Cloudflare 官方 IPv6 IP 列表"
    download_if_missing "$DEFAULT_IPV6_LIST" "$IP_FILE"
  else
    log "准备 Cloudflare 官方 IPv4 IP 列表"
    download_if_missing "$DEFAULT_IPV4_LIST" "$IP_FILE"
  fi
}

prepare_reverse_ip_list() {
  local zip_path="$APP_DIR/txt.zip"
  local txt_dir="$APP_DIR/txt"

  log "准备 CDN 反代 IP 库"
  if [ ! -s "$zip_path" ]; then
    log "下载反代 IP 库：$REVERSE_ZIP_PRIMARY"
    if ! curl -fL --connect-timeout 10 --max-time 180 --retry 1 -o "$zip_path" "$REVERSE_ZIP_PRIMARY"; then
      log "主下载地址失败，尝试备用地址：$REVERSE_ZIP_FALLBACK"
      curl -fL --connect-timeout 10 --max-time 180 --retry 2 -o "$zip_path" "$REVERSE_ZIP_FALLBACK"
    fi
  else
    log "检测到已有反代 IP 库：$zip_path"
  fi

  rm -rf "$txt_dir"
  mkdir -p "$txt_dir"
  unzip -o "$zip_path" -d "$txt_dir" >/dev/null 2>&1 || die "反代 IP 库解压失败"

  log "按端口 $CFST_PORT 筛选反代 IP"
  if [ "$CFST_PORT" = "443" ]; then
    find "$txt_dir" -type f -name "*443*" ! -name "*8443*" -exec cat {} \; > "$IP_FILE"
  elif [ "$CFST_PORT" = "80" ]; then
    find "$txt_dir" -type f -name "*80*" ! -name "*8880*" ! -name "*8080*" -exec cat {} \; > "$IP_FILE"
  else
    find "$txt_dir" -type f -name "*${CFST_PORT}*" -exec cat {} \; > "$IP_FILE"
  fi

  if [ ! -s "$IP_FILE" ]; then
    die "反代 IP 列表为空，请更换端口或重新下载 IP 库"
  fi

  grep -E '^8|^47|^43|^130|^132|^152|^193|^140|^138|^150|^143|^141|^155|^168|^124|^170|^119' "$IP_FILE" > "$APP_DIR/pass.txt" && mv "$APP_DIR/pass.txt" "$IP_FILE" || true
  log "反代 IP 列表准备完成：$(wc -l < "$IP_FILE" | tr -d ' ') 条"
}

isp_profile_url() {
  case "$1" in
    cmcc) printf '%s\n' "https://raw.githubusercontent.com/cmliu/cmliu/main/CF-CIDR/cmcc.txt" ;;
    cu) printf '%s\n' "https://raw.githubusercontent.com/cmliu/cmliu/main/CF-CIDR/cu.txt" ;;
    ct) printf '%s\n' "https://raw.githubusercontent.com/cmliu/cmliu/main/CF-CIDR/ct.txt" ;;
    cf) printf '%s\n' "https://raw.githubusercontent.com/cmliu/cmliu/main/CF-CIDR.txt" ;;
    *) return 1 ;;
  esac
}

url_host() {
  printf '%s\n' "$1" | sed -e 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' -e 's#/.*##' -e 's#^\[\(.*\)\]$#\1#' -e 's#:[0-9][0-9]*$##'
}

external_url_allowed() {
  local url="$1" host allowed
  case "$url" in
    https://*) ;;
    *) return 1 ;;
  esac
  host="$(url_host "$url" | tr 'A-Z' 'a-z')"
  [ -n "$host" ] || return 1
  printf '%s\n' "$host" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$|:' && return 1
  case "$host" in
    localhost|*.localhost|127.*|10.*|172.16.*|172.17.*|172.18.*|172.19.*|172.2?.*|172.30.*|172.31.*|192.168.*|169.254.*|0.*|::1) return 1 ;;
  esac
  for allowed in $CFST_EXTERNAL_CANDIDATE_ALLOWED_HOSTS; do
    [ "$host" = "$(printf '%s' "$allowed" | tr 'A-Z' 'a-z')" ] && return 0
  done
  return 1
}

download_external_candidate_source() {
  local url="$1" output="$2"
  external_url_allowed "$url" || {
    printf 'reject_url\t%s\tinvalid_protocol_or_host\n' "$url" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
    return 1
  }
  if curl -fsS --connect-timeout 10 --max-time 30 --retry 1 --retry-delay 1 "$url" \
    | head -c "$CFST_EXTERNAL_CANDIDATE_MAX_BYTES" \
    | awk -v max_lines="$CFST_EXTERNAL_CANDIDATE_MAX_LINES" 'NR <= max_lines {print}' > "$output"; then
    printf 'source_ok\t%s\tbytes=%s\tlines=%s\n' "$url" "$(wc -c < "$output" | tr -d ' ')" "$(wc -l < "$output" | tr -d ' ')" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
    return 0
  fi
  printf 'source_error\t%s\tdownload_failed\n' "$url" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
  return 1
}

normalize_candidate_ips() {
  awk -v ip_version="$IP_VERSION" -v limit="$CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT" '
    function emit(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^\[/, "", value)
      gsub(/\]$/, "", value)
      if (value == "" || length(value) > 80) return
      is_v6 = (value ~ /:/)
      is_v4 = (value ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/)
      is_v6_cidr = (value ~ /^[0-9A-Fa-f:]+(\/[0-9]+)?$/ && is_v6)
      if (ip_version == "ipv6") {
        if (!is_v6_cidr) return
      } else {
        if (!is_v4) return
      }
      if (!seen[value]++ && count < limit) {
        print value
        count++
      }
    }
    {
      line=$0
      sub(/\r$/, "", line)
      sub(/#.*/, "", line)
      gsub(/"/, "", line)
      gsub(/\t/, ",", line)
      n=split(line, parts, ",")
      for (i=1; i<=n; i++) {
        token=parts[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", token)
        if (token == "" || token ~ /IP|地址|延迟|下载速度|端口|国家|城市|数据中心/) continue
        if (token ~ /^\[[0-9A-Fa-f:]+\]:[0-9]+$/) {
          sub(/^\[/, "", token)
          sub(/\]:[0-9]+$/, "", token)
        } else if (token ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$/) {
          sub(/:[0-9]+$/, "", token)
        }
        emit(token)
      }
    }
  '
}

cloudflare_filter_candidates() {
  local ranges_file="$1"
  if [ "$IP_VERSION" = "ipv6" ]; then
    printf 'reject_ipv6\tfail_closed_ipv6_cidr_filter_not_supported\n' >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
    return 0
  fi
  awk '
    function ip2int(ip, parts) {
      split(ip, parts, ".")
      return parts[1] * 16777216 + parts[2] * 65536 + parts[3] * 256 + parts[4]
    }
    function prefix_match(ip, base, prefix, octets, rem, ip_parts, base_parts, mask, i) {
      split(ip, ip_parts, ".")
      split(base, base_parts, ".")
      octets=int(prefix / 8)
      rem=prefix % 8
      for (i=1; i<=octets; i++) {
        if ((ip_parts[i] + 0) != (base_parts[i] + 0)) return 0
      }
      if (rem == 0) return 1
      mask=256 - (2 ^ (8 - rem))
      return int((ip_parts[octets + 1] + 0) / (256 - mask)) == int((base_parts[octets + 1] + 0) / (256 - mask))
    }
    function in_cidr(ip, cidr, a, base, prefix) {
      split(cidr, a, "/")
      base=a[1]
      prefix=(a[2] == "" ? 32 : a[2] + 0)
      if (ip !~ /^[0-9]+\./ || base !~ /^[0-9]+\./) return 0
      if (prefix < 0 || prefix > 32) return 0
      return prefix_match(ip, base, prefix)
    }
    FNR == NR {
      if ($1 != "") cidr[++cidr_count]=$1
      next
    }
    $1 != "" {
      ok=0
      for (i=1; i<=cidr_count; i++) {
        if (in_cidr($1, cidr[i])) {ok=1; break}
      }
      if (ok && !seen[$1]++) print $1
    }
  ' "$ranges_file" -
}

prepare_external_candidates_to_file() {
  local output="$1" source_dir source_file normalized_file ranges_file url count profile_url
  mkdir -p "$APP_DIR"
  source_dir="$APP_DIR/external-candidate-sources"
  rm -rf "$source_dir"
  mkdir -p "$source_dir"
  : > "$EXTERNAL_CANDIDATE_REPORT_FILE"
  : > "$output"
  printf 'checked_at\t%s\n' "$(date '+%F %T')" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
  printf 'ip_version\t%s\n' "$IP_VERSION" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"

  count=0
  if [ -n "$CFST_ISP_PROFILE" ]; then
    profile_url="$(isp_profile_url "$CFST_ISP_PROFILE")" || profile_url=""
    if [ -n "$profile_url" ]; then
      count=$((count + 1))
      source_file="$source_dir/source-$count.txt"
      download_external_candidate_source "$profile_url" "$source_file" || true
    fi
  fi
  for url in $CFST_EXTERNAL_CANDIDATE_URLS; do
    count=$((count + 1))
    if [ "$count" -gt "$CFST_EXTERNAL_CANDIDATE_URL_LIMIT" ]; then
      printf 'reject_url\t%s\turl_limit_exceeded\n' "$url" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
      continue
    fi
    source_file="$source_dir/source-$count.txt"
    download_external_candidate_source "$url" "$source_file" || true
  done

  normalized_file="$APP_DIR/external-candidates.normalized.tmp"
  : > "$normalized_file"
  for source_file in "$source_dir"/source-*.txt; do
    [ -s "$source_file" ] || continue
    normalize_candidate_ips < "$source_file" >> "$normalized_file"
  done

  ranges_file="$APP_DIR/external-candidates.cloudflare-ranges.tmp"
  if [ "$IP_VERSION" = "ipv6" ]; then
    download_if_missing "$DEFAULT_IPV6_LIST" "$ranges_file"
  else
    download_if_missing "$DEFAULT_IPV4_LIST" "$ranges_file"
  fi
  if [ -s "$normalized_file" ] && [ -s "$ranges_file" ]; then
    cloudflare_filter_candidates "$ranges_file" < "$normalized_file" | awk -v limit="$CFST_EXTERNAL_CANDIDATE_LIMIT" 'NF && !seen[$1]++ && count < limit {print $1; count++}' > "$output"
  fi
  printf 'normalized_count\t%s\n' "$(wc -l < "$normalized_file" 2>/dev/null | tr -d ' ')" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
  printf 'accepted_count\t%s\n' "$(wc -l < "$output" 2>/dev/null | tr -d ' ')" >> "$EXTERNAL_CANDIDATE_REPORT_FILE"
}

merge_external_candidates_if_enabled() {
  [ "${CFST_EXTERNAL_CANDIDATES:-0}" = "1" ] || return 0
  local external_file merged_file base_count external_count merged_count
  external_file="$APP_DIR/external-candidates.runtime.txt"
  prepare_external_candidates_to_file "$external_file"
  [ -s "$external_file" ] || {
    log "外部候选源：未获得可用 Cloudflare 候选，继续使用基础 IP 列表"
    return 0
  }
  base_count="$(wc -l < "$IP_FILE" | tr -d ' ')"
  external_count="$(wc -l < "$external_file" | tr -d ' ')"
  merged_file="/tmp/cf-dns-speedup-ip-merged.$$"
  awk 'NF && !seen[$1]++ {print $1}' "$IP_FILE" "$external_file" > "$merged_file"
  EXTERNAL_RUNTIME_IP_FILE="$merged_file"
  IP_FILE="$merged_file"
  merged_count="$(wc -l < "$IP_FILE" | tr -d ' ')"
  log "外部候选源：已临时追加 $external_count 条，基础 $base_count 条，合并后 $merged_count 条；不改写生产 ip.txt"
}

prepare_assets() {
  mkdir -p "$APP_DIR"
  prepare_cfst
  if [ "$CDN_IP_MODE" = "reverse" ]; then
    prepare_reverse_ip_list
  else
    prepare_official_ip_list
  fi
  merge_external_candidates_if_enabled
  [ -s "$IP_FILE" ] || die "IP 列表为空：$IP_FILE"
  log "IP 列表准备完成：$(wc -l < "$IP_FILE" | tr -d ' ') 条"
}

plugin_to_service() {
  case "$1" in
    1) echo passwall ;;
    2) echo passwall2 ;;
    3) echo shadowsocksr ;;
    4) echo clash ;;
    5) echo openclash ;;
    6) echo bypass ;;
    7) echo v2raya ;;
    8) echo vssr ;;
    9) echo homeproxy ;;
    10) echo nikki ;;
    11) echo shellcrash ;;
    *) echo "" ;;
  esac
}

stop_proxy_if_needed() {
  PROXY_SERVICE="$(plugin_to_service "$PROXY_PLUGIN")"
  if [ -z "$PROXY_SERVICE" ]; then
    log "代理插件控制：未选择代理插件，不停止任何服务"
    return 0
  fi
  if [ ! -x "/etc/init.d/$PROXY_SERVICE" ]; then
    log "代理插件控制：未找到 /etc/init.d/$PROXY_SERVICE，跳过停止"
    return 0
  fi
  log "代理插件控制：停止 $PROXY_SERVICE，避免优选结果受代理影响"
  if timeout 30 "/etc/init.d/$PROXY_SERVICE" stop; then
    PROXY_STOPPED=1
    log "代理插件控制：$PROXY_SERVICE 已停止"
  else
    log "警告：停止 $PROXY_SERVICE 超时或失败，继续执行"
  fi
}

restart_proxy_if_needed() {
  if [ "$PROXY_STOPPED" != "1" ] || [ -z "$PROXY_SERVICE" ]; then
    return 0
  fi
  if [ -x "/etc/init.d/$PROXY_SERVICE" ]; then
    log "代理插件控制：重启 $PROXY_SERVICE"
    timeout 30 "/etc/init.d/$PROXY_SERVICE" restart || log "警告：重启 $PROXY_SERVICE 失败，请手动检查"
    log "代理插件控制：等待 $PROXY_RESTART_WAIT 秒"
    sleep "$PROXY_RESTART_WAIT"
  fi
  PROXY_STOPPED=0
}

cleanup_on_exit() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ] && [ "$RUN_STATUS" != "failed" ]; then
    RUN_STATUS="failed"
    RUN_ERROR="script exited with status $exit_code"
  fi
  restart_proxy_if_needed || true
  if [ -n "$RUN_STARTED_AT" ]; then
    [ "$RUN_STATUS" = "not-started" ] && RUN_STATUS="success"
    write_run_summary || true
  fi
  if [ -n "$EXTERNAL_RUNTIME_IP_FILE" ] && [ -f "$EXTERNAL_RUNTIME_IP_FILE" ]; then
    rm -f "$EXTERNAL_RUNTIME_IP_FILE"
  fi
  release_lock
}

source_optional_lib() {
  local lib_path="$1"
  [ -f "$lib_path" ] || return 0
  # shellcheck disable=SC1090
  . "$lib_path"
}

check_cloudflare_auth() {
  require_cloudflare_config
  log "Cloudflare：验证 Token 和 Zone 权限"
  local status
  status="$(curl -sS -o "$APP_DIR/cf-zone.json" -w '%{http_code}' \
    --connect-timeout 10 --max-time 20 \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID")"
  [ "$status" = "200" ] || die "Cloudflare Zone API 返回 HTTP $status"
  jq -e '.success == true' "$APP_DIR/cf-zone.json" >/dev/null || die "Cloudflare Token 或 Zone ID 验证失败"
  log "Cloudflare：验证成功"
}

run_speedtest() {
  local current max_count step qualified
  local best_result_file="$APP_DIR/result.best.csv"
  local best_qualified=-1
  local best_download_count="$CFST_DOWNLOAD_COUNT"
  rm -f "$best_result_file" "$STABILITY_RESULT_FILE"
  current="$CFST_DOWNLOAD_COUNT"
  max_count="$CFST_DOWNLOAD_COUNT_MAX"
  step="$CFST_DOWNLOAD_COUNT_STEP"
  [ "$max_count" -ge "$current" ] 2>/dev/null || max_count="$current"
  [ "$step" -ge 0 ] 2>/dev/null || step=0

  while true; do
    run_cfst_once "$current"
    qualified="$(preferred_result_count)"
    if [ "$qualified" -gt "$best_qualified" ]; then
      cp "$RESULT_FILE" "$best_result_file"
      best_qualified="$qualified"
      best_download_count="$current"
    fi
    if [ "${CFST_PREFER_MIN_SPEED:-0}" != "0" ]; then
      log "测速：速度不低于 ${CFST_PREFER_MIN_SPEED} MB/s 的候选数量：$qualified/$CFST_RESULT_COUNT"
    fi
    if [ "${CFST_PREFER_MIN_SPEED:-0}" = "0" ] || [ "$qualified" -ge "$CFST_RESULT_COUNT" ]; then
      CFST_DOWNLOAD_COUNT="$current"
      break
    fi
    if [ "$step" -le 0 ] || [ "$current" -ge "$max_count" ]; then
      log "测速：高吞吐候选不足 $CFST_RESULT_COUNT 个，已到当前上限 $current；将用最高速度结果补齐，避免域名缺少 IP"
      CFST_DOWNLOAD_COUNT="$current"
      break
    fi
    local next
    next=$((current + step))
    [ "$next" -le "$max_count" ] || next="$max_count"
    log "测速：高吞吐候选不足，扩大下载测速数量：$current -> $next"
    current="$next"
  done

  if [ -s "$best_result_file" ] && [ "$best_download_count" != "$CFST_DOWNLOAD_COUNT" ]; then
    cp "$best_result_file" "$RESULT_FILE"
    CFST_DOWNLOAD_COUNT="$best_download_count"
    log "测速：采用高吞吐候选最多的一轮结果，下载测速数量 $best_download_count，达标候选 $best_qualified/$CFST_RESULT_COUNT"
  fi

  run_stability_retest
}

run_cfst_once() {
  local download_count="$1"
  rm -f "$RESULT_FILE"
  local args
  args="-tp $CFST_PORT -t $CFST_TIMEOUT -n $CFST_THREADS -dn $download_count -p $download_count -tl $CFST_MAX_LATENCY -tll $CFST_MIN_LATENCY -sl $CFST_MIN_SPEED -dt $CFST_DOWNLOAD_TIMEOUT -f $IP_FILE -o $RESULT_FILE"
  if [ -n "$CFST_URL" ]; then
    args="$args -url $CFST_URL"
    log "测速：已开启下载测速，地址 $CFST_URL"
  else
    args="$args -dd"
    log "测速：未开启下载测速，仅做延迟优选"
  fi

  log "测速：端口 $CFST_PORT，线程 $CFST_THREADS，下载测速数量 $download_count，显示数量 $CFST_RESULT_COUNT，总超时 ${CFST_TOTAL_TIMEOUT}s"
  log "测速：下面显示 cfst 实时进度和速度；主日志只记录关键步骤，避免进度刷屏"
  local cfst_raw_log="$CFST_RAW_LOG"
  : > "$cfst_raw_log"
  if [ -t 1 ]; then
    # cfst 检测到真实终端时会用同一行刷新进度；不要通过 tee 管道输出。
    # shellcheck disable=SC2086
    if ! timeout "$CFST_TOTAL_TIMEOUT" "$CFST_BIN" $args; then
      die "cfst 执行失败或超过总超时，请查看 $LOG_FILE"
    fi
  else
    log "测速：非交互运行，cfst 原始输出写入 $cfst_raw_log"
    # shellcheck disable=SC2086
    if ! timeout "$CFST_TOTAL_TIMEOUT" "$CFST_BIN" $args >"$cfst_raw_log" 2>&1; then
      tail -n 80 "$cfst_raw_log" >>"$LOG_FILE" 2>/dev/null || true
      die "cfst 执行失败或超过总超时，请查看 $cfst_raw_log"
    fi
  fi

  [ -s "$RESULT_FILE" ] || die "cfst 未生成 result.csv"
  local first_ip
  first_ip="$(awk -F, 'NR==2 {gsub(/[[:space:]]/, "", $1); print $1}' "$RESULT_FILE")"
  [ -n "$first_ip" ] || die "result.csv 没有可用 IP"
  log "测速：优选完成，最快 IP：$first_ip"
}

preferred_result_count() {
  awk -F, -v min_speed="${CFST_PREFER_MIN_SPEED:-0}" 'NR>1 && $1 != "" && ($6 + 0) >= min_speed {count++} END {print count + 0}' "$RESULT_FILE"
}

cfst_url_host() {
  printf '%s\n' "$CFST_URL" | sed -e 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' -e 's#/.*##' -e 's#^\[\(.*\)\]$#\1#' -e 's#:[0-9][0-9]*$##'
}

download_speed_bps() {
  local host="$1"
  local ip="$2"
  curl -L -k -o /dev/null \
    --connect-timeout "$CFST_STABILITY_CONNECT_TIMEOUT" \
    --max-time "$CFST_STABILITY_TIMEOUT" \
    --resolve "$host:$CFST_PORT:$ip" \
    -w '%{http_code} %{size_download} %{speed_download}' \
    "$CFST_URL" 2>/dev/null | awk '$1 == 200 && $2 > 0 {print $3 + 0}' || true
}

current_dns_candidate_rows() {
  [ "${CFST_COMPARE_CURRENT_DNS:-0}" = "1" ] || return 0
  local names qtype
  names="$CF_RECORD_NAMES"
  [ -n "$names" ] || names="$CF_RECORD_NAME"
  [ -n "$names" ] || return 0
  case "$IP_VERSION" in
    ipv6) qtype="AAAA" ;;
    *) qtype="A" ;;
  esac
  for name in $names; do
    if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ] && command -v jq >/dev/null 2>&1; then
      local api response ip
      api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=$qtype&name=$name"
      response="$(cf_api GET "$api" 2>/dev/null || true)"
      echo "$response" | jq -r '.result[]?.content // empty' 2>/dev/null | awk -v source="current_dns" '
        $1 != "" && !seen[$1]++ {print $1 "\t0\t0\t" source}
      '
    elif command -v nslookup >/dev/null 2>&1; then
      nslookup "$name" 127.0.0.1 2>/dev/null | awk -v source="current_dns" '
        /^Address [0-9]+: / && $3 !~ /^(127\.|::1)/ && !seen[$3]++ {print $3 "\t0\t0\t" source}
        /^Address: / && $2 !~ /^(127\.|::1)/ && !seen[$2]++ {print $2 "\t0\t0\t" source}
      '
    fi
  done
}

champion_pool_candidate_rows() {
  [ "${CFST_CHAMPION_POOL:-0}" = "1" ] || return 0
  [ -s "$CHAMPION_POOL_FILE" ] || return 0
  awk -F '\t' 'NR > 1 && $1 != "" {print $1 "\t0\t" ($2 + 0) "\tchampion"}' "$CHAMPION_POOL_FILE"
}

observation_candidate_rows() {
  [ "${CFST_OBSERVATION_CANDIDATES:-1}" = "1" ] || return 0
  [ -s "$OBSERVATION_HISTORY_FILE" ] || return 0
  awk -F '\t' -v min_speed="${CFST_OBSERVATION_CANDIDATE_MIN_SPEED:-8}" '
    NR == 1 {next}
    $2 != "" {
      ip=$2
      count[ip]++
      recent_min[ip]=$5+0
      if (($7+0) > 0) recent_ok[ip]=$7+0
      if (($5+0) < min_speed || ($7+0) < 1) low[ip]++
      seen[ip]=1
    }
    END {
      for (ip in seen) {
        if (count[ip] > 0 && recent_min[ip] >= min_speed && recent_ok[ip] >= 1) {
          source = low[ip] == 0 ? "observation" : "observation_watch"
          print ip "\t0\t" recent_min[ip] "\t" source
        }
      }
    }
  ' "$OBSERVATION_HISTORY_FILE"
}

build_stability_candidates() {
  local raw_file="$APP_DIR/stability-candidates.raw.tsv"
  : > "$raw_file"
  current_dns_candidate_rows >> "$raw_file"
  observation_candidate_rows >> "$raw_file"
  champion_pool_candidate_rows >> "$raw_file"
  awk -F, -v limit="$CFST_STABILITY_TEST_COUNT" -v min_speed="${CFST_PREFER_MIN_SPEED:-0}" '
    NR == 1 {next}
    $1 != "" {
      ip=$1
      gsub(/[[:space:]]/, "", ip)
      row=ip "\t" $5 "\t" $6 "\tnew"
      if (min_speed > 0 && ($6 + 0) >= min_speed) preferred[++preferred_count]=row
      else fallback[++fallback_count]=row
    }
    END {
      count=0
      for (i=1; i<=preferred_count && count<limit; i++) {print preferred[i]; count++}
      for (i=1; i<=fallback_count && count<limit; i++) {print fallback[i]; count++}
    }
  ' "$RESULT_FILE" >> "$raw_file"

  awk -F '\t' -v limit="${CFST_FINAL_CANDIDATE_LIMIT:-20}" '
    $1 != "" {
      ip=$1
      if (!(ip in seen)) {
        order[++count]=ip
        latency[ip]=$2
        speed[ip]=$3
        source[ip]=$4
        seen[ip]=1
      } else {
        if (source[ip] !~ "(^|,)" $4 "(,|$)") source[ip]=source[ip] "," $4
        if (($3 + 0) > (speed[ip] + 0)) speed[ip]=$3
        if ((latency[ip] + 0) == 0 && ($2 + 0) > 0) latency[ip]=$2
      }
    }
    END {
      for (i=1; i<=count && printed<limit; i++) {
        ip=order[i]
        print ip "\t" latency[ip] "\t" speed[ip] "\t" source[ip]
        printed++
      }
    }
  ' "$raw_file"
}

sort_stability_results() {
  awk -F '\t' \
    -v retain_ratio="${CFST_RETAIN_RATIO:-0.90}" \
    -v replace_ratio="${CFST_REPLACE_IMPROVE_RATIO:-1.25}" \
    -v degrade_min="${CFST_DEGRADE_MIN_SPEED:-2}" \
    -v retain_min="${CFST_RETAIN_MIN_SPEED:-8}" \
    -v rounds="${CFST_STABILITY_TEST_ROUNDS:-0}" '
    {
      line[NR]=$0
      min_speed[NR]=$4 + 0
      avg_speed[NR]=$5 + 0
      ok_rounds[NR]=$6 + 0
      source[NR]=$7
      boost[NR]=1
      stable_enough=(min_speed[NR] >= retain_min && (rounds <= 0 || ok_rounds[NR] >= rounds))
      if (source[NR] ~ /(^|,)current_dns(,|$)/ && stable_enough) boost[NR]=replace_ratio
      else if (source[NR] ~ /(^|,)champion(,|$)/ && stable_enough) boost[NR]=1 / retain_ratio
      else if (min_speed[NR] < degrade_min) boost[NR]=0.5
      score[NR]=min_speed[NR] * boost[NR]
    }
    END {
      for (i=1; i<=NR; i++) {
        best=i
        for (j=i+1; j<=NR; j++) {
          if (score[j] > score[best] || (score[j] == score[best] && min_speed[j] > min_speed[best]) || (score[j] == score[best] && min_speed[j] == min_speed[best] && avg_speed[j] > avg_speed[best])) best=j
        }
        if (best != i) {
          tmp=line[i]; line[i]=line[best]; line[best]=tmp
          tmp=min_speed[i]; min_speed[i]=min_speed[best]; min_speed[best]=tmp
          tmp=avg_speed[i]; avg_speed[i]=avg_speed[best]; avg_speed[best]=tmp
          tmp=score[i]; score[i]=score[best]; score[best]=tmp
        }
        print line[i]
      }
    }
  '
}

apply_dual_pool_slots() {
  if [ "${CFST_DUAL_POOL_MODE:-1}" != "1" ] || [ ! -s "$OBSERVATION_HISTORY_FILE" ]; then
    cat
    return 0
  fi

  awk -F '\t' \
    -v obs_file="$OBSERVATION_HISTORY_FILE" \
    -v stable_slots="${CFST_STABLE_SLOT_COUNT:-3}" \
    -v result_count="${CFST_RESULT_COUNT:-5}" \
    -v min_speed="${CFST_STABLE_SLOT_MIN_SPEED:-8}" \
    -v fallback_min_speed="${CFST_STABLE_SLOT_FALLBACK_MIN_SPEED:-6.5}" \
    -v prefer_regex="${CFST_STABLE_SLOT_PREFER_REGEX:-^104\\.17\\.}" \
    -v avoid_regex="${CFST_STABLE_SLOT_AVOID_REGEX:-^(104\\.20\\.|104\\.26\\.|172\\.67\\.)}" \
    -v allow_challenger="${CFST_STABLE_SLOT_ALLOW_CHALLENGER:-0}" \
    -v allow_avoid="${CFST_STABLE_SLOT_ALLOW_AVOID:-0}" \
    -v stale_low_count="${CFST_OBSERVATION_STALE_LOW_COUNT:-3}" \
    -v stable_max_low="${CFST_OBSERVATION_STABLE_MAX_LOW_COUNT:-1}" \
    -v recent_window="${CFST_OBSERVATION_RECENT_WINDOW:-2}" \
    -v rounds="${CFST_STABILITY_TEST_ROUNDS:-0}" '
    function add_pick(idx) {
      if (idx <= 0 || picked[idx] || emitted >= result_count) return
      picked[idx]=1
      print line[idx]
      emitted++
    }
    function add_group(arr, count, limit, i) {
      for (i=1; i<=count && emitted<limit; i++) add_pick(arr[i])
    }
    function classify(ip, recent_start, recent_lows) {
      if (obs_count[ip] == 0) return "challenger"
      recent_start=obs_count[ip] - recent_window + 1
      if (recent_start < 1) recent_start=1
      recent_lows=0
      for (k=recent_start; k<=obs_count[ip]; k++) if (obs_min[ip,k] < fallback_min_speed || obs_ok[ip,k] < 1) recent_lows++
      if (obs_low[ip] >= stale_low_count || recent_lows >= recent_window) return "stale"
      if (obs_low[ip] <= stable_max_low && obs_recent_min[ip] >= fallback_min_speed && obs_recent_ok[ip] >= 1) return "stable"
      return "watch"
    }
    function stable_score(idx, health, score) {
      health=health_status[idx]
      score=(obs_avg_min[ip[idx]] * 0.60) + (current_min[idx] * 0.30) + (cfst_speed[idx] * 0.10)
      if (health == "stable") score += 20
      else if (health == "watch") score += 5
      else if (health == "stale") score -= 1000
      else score -= 10
      if (ip[idx] ~ prefer_regex) score += 2
      if (ip[idx] ~ avoid_regex) score -= 5
      return score
    }
    function competitive_score(idx, health, score) {
      health=health_status[idx]
      score=(current_min[idx] * 0.60) + (cfst_speed[idx] * 0.30) + (obs_avg_min[ip[idx]] * 0.10)
      if (health == "stale") score -= 100
      if (ip[idx] ~ avoid_regex) score -= 1
      return score
    }
    BEGIN {
      while ((getline row < obs_file) > 0) {
        split(row, f, "\t")
        if (f[1] == "observed_at" || f[2] == "") continue
        ip0=f[2]
        obs_count[ip0]++
        idx=obs_count[ip0]
        obs_min[ip0,idx]=f[5]+0
        obs_ok[ip0,idx]=f[7]+0
        obs_recent_min[ip0]=f[5]+0
        obs_recent_ok[ip0]=f[7]+0
        obs_sum_min[ip0]+=f[5]+0
        obs_avg_min[ip0]=obs_sum_min[ip0] / obs_count[ip0]
        if ((f[5]+0) < fallback_min_speed || (f[7]+0) < 1) obs_low[ip0]++
      }
      close(obs_file)
    }
    $1 != "" {
      line[++n]=$0
      ip[n]=$1
      latency[n]=$2+0
      cfst_speed[n]=$3+0
      current_min[n]=$4+0
      avg_speed[n]=$5+0
      ok_rounds[n]=$6+0
      source[n]=$7
      enough_rounds=(rounds <= 0 || ok_rounds[n] >= rounds)
      health_status[n]=classify(ip[n])
      stable_rank[n]=stable_score(n)
      competitive_rank[n]=competitive_score(n)
      if (current_min[n] >= fallback_min_speed && enough_rounds && health_status[n] == "stable") stable[++stable_count]=n
      else if (current_min[n] >= fallback_min_speed && enough_rounds && health_status[n] == "watch") watch[++watch_count]=n
      else if (health_status[n] != "stale") competitive[++competitive_count]=n
      else stale[++stale_count]=n
    }
    END {
      for (i=1; i<=stable_count; i++) {
        best=i
        for (j=i+1; j<=stable_count; j++) if (stable_rank[stable[j]] > stable_rank[stable[best]]) best=j
        tmp=stable[i]; stable[i]=stable[best]; stable[best]=tmp
      }
      for (i=1; i<=watch_count; i++) {
        best=i
        for (j=i+1; j<=watch_count; j++) if (stable_rank[watch[j]] > stable_rank[watch[best]]) best=j
        tmp=watch[i]; watch[i]=watch[best]; watch[best]=tmp
      }
      for (i=1; i<=competitive_count; i++) {
        best=i
        for (j=i+1; j<=competitive_count; j++) if (competitive_rank[competitive[j]] > competitive_rank[competitive[best]]) best=j
        tmp=competitive[i]; competitive[i]=competitive[best]; competitive[best]=tmp
      }
      add_group(stable, stable_count, stable_slots)
      add_group(watch, watch_count, stable_slots)
      for (i=1; i<=competitive_count && emitted<stable_slots; i++) {
        idx=competitive[i]
        if (allow_challenger == "1" && (allow_avoid == "1" || ip[idx] !~ avoid_regex)) add_pick(idx)
      }
      add_group(competitive, competitive_count, result_count)
      add_group(stable, stable_count, result_count)
      add_group(watch, watch_count, result_count)
      for (i=1; i<=n && emitted<result_count; i++) add_pick(i)
    }
  '
}

promote_primary_safe_candidate() {
  if [ "${CFST_PRIMARY_SAFE_MODE:-1}" != "1" ] || [ ! -s "$OBSERVATION_HISTORY_FILE" ]; then
    cat
    return 0
  fi

  awk -F '\t' \
    -v obs_file="$OBSERVATION_HISTORY_FILE" \
    -v min_speed="${CFST_PRIMARY_MIN_SPEED:-8}" \
    -v fallback_min_speed="${CFST_PRIMARY_FALLBACK_MIN_SPEED:-6.5}" \
    -v prefer_regex="${CFST_PRIMARY_PREFER_REGEX:-^104\\.17\\.}" \
    -v avoid_regex="${CFST_PRIMARY_AVOID_REGEX:-^(104\\.20\\.|104\\.26\\.|172\\.67\\.)}" \
    -v allow_challenger="${CFST_PRIMARY_ALLOW_CHALLENGER:-0}" '
    BEGIN {
      while ((getline row < obs_file) > 0) {
        split(row, f, "\t")
        if (f[1] == "observed_at" || f[2] == "") continue
        ip=f[2]
        count[ip]++
        if ((f[5]+0) < fallback_min_speed || (f[7]+0) < 1) low[ip]++
      }
      close(obs_file)
    }
    $1 != "" {
      line[++n]=$0
      ip[n]=$1
      speed[n]=$4+0
      active=(speed[n] >= fallback_min_speed && (allow_challenger == "1" || count[$1] > 0) && low[$1] == 0)
      if (active && $1 ~ prefer_regex) {
        if (best_prefer == 0 || speed[n] > speed[best_prefer]) best_prefer=n
      } else if (active && $1 !~ avoid_regex) {
        if (best_neutral == 0 || speed[n] > speed[best_neutral]) best_neutral=n
      } else if (active) {
        if (best_avoid == 0 || speed[n] > speed[best_avoid]) best_avoid=n
      }
    }
    END {
      pick=best_prefer ? best_prefer : (best_neutral ? best_neutral : best_avoid)
      if (pick == 0 || pick == 1) {
        for (i=1; i<=n; i++) print line[i]
      } else {
        print line[pick]
        for (i=1; i<=n; i++) if (i != pick) print line[i]
      }
    }
  '
}

promote_stable_slots() {
  if [ "${CFST_STABLE_SLOT_MODE:-1}" != "1" ] || [ "${CFST_STABLE_SLOT_COUNT:-0}" -le 0 ] 2>/dev/null || [ ! -s "$OBSERVATION_HISTORY_FILE" ]; then
    cat
    return 0
  fi

  awk -F '\t' \
    -v obs_file="$OBSERVATION_HISTORY_FILE" \
    -v slot_count="${CFST_STABLE_SLOT_COUNT:-3}" \
    -v min_speed="${CFST_STABLE_SLOT_MIN_SPEED:-8}" \
    -v fallback_min_speed="${CFST_STABLE_SLOT_FALLBACK_MIN_SPEED:-6.5}" \
    -v prefer_regex="${CFST_STABLE_SLOT_PREFER_REGEX:-^104\\.17\\.}" \
    -v avoid_regex="${CFST_STABLE_SLOT_AVOID_REGEX:-^(104\\.20\\.|104\\.26\\.|172\\.67\\.)}" \
    -v allow_challenger="${CFST_STABLE_SLOT_ALLOW_CHALLENGER:-0}" \
    -v allow_avoid="${CFST_STABLE_SLOT_ALLOW_AVOID:-0}" \
    -v rounds="${CFST_STABILITY_TEST_ROUNDS:-0}" '
    function add_pick(idx) {
      if (idx <= 0 || picked[idx]) return
      picked[idx]=1
      print line[idx]
      emitted++
    }
    BEGIN {
      while ((getline row < obs_file) > 0) {
        split(row, f, "\t")
        if (f[1] == "observed_at" || f[2] == "") continue
        ip=f[2]
        obs_count[ip]++
        obs_recent_min[ip]=f[5]+0
        obs_recent_ok[ip]=f[7]+0
        if ((f[5]+0) < fallback_min_speed || (f[7]+0) < 1) obs_low[ip]++
      }
      close(obs_file)
    }
    $1 != "" {
      line[++n]=$0
      ip[n]=$1
      current_min[n]=$4+0
      ok[n]=$6+0
      enough_rounds=(rounds <= 0 || ok[n] >= rounds)
      observed_stable=(obs_count[$1] > 0 && obs_low[$1] == 0 && obs_recent_min[$1] >= fallback_min_speed && obs_recent_ok[$1] >= 1)
      challenger_ok=(allow_challenger == "1" && obs_count[$1] == 0)
      stable[n]=(current_min[n] >= fallback_min_speed && enough_rounds && (observed_stable || challenger_ok))
      if (stable[n] && $1 ~ prefer_regex) prefer[++prefer_count]=n
      else if (stable[n] && $1 !~ avoid_regex) neutral[++neutral_count]=n
      else if (stable[n] && allow_avoid == "1") avoid[++avoid_count]=n
    }
    END {
      for (i=1; i<=prefer_count && emitted<slot_count; i++) add_pick(prefer[i])
      for (i=1; i<=neutral_count && emitted<slot_count; i++) add_pick(neutral[i])
      for (i=1; i<=avoid_count && emitted<slot_count; i++) add_pick(avoid[i])
      for (i=1; i<=n; i++) add_pick(i)
    }
  '
}


update_external_observation_pool() {
  [ "${CFST_EXTERNAL_CANDIDATES:-0}" = "1" ] || return 0
  [ "${CFST_EXTERNAL_OBSERVATION_POOL:-1}" = "1" ] || return 0
  [ -s "$STABILITY_RESULT_FILE" ] || return 0
  local external_file="$APP_DIR/external-candidates.runtime.txt"
  [ -s "$external_file" ] || return 0

  local tmp old matched now source_label
  tmp="$APP_DIR/external-observation-pool.tmp"
  old="$APP_DIR/external-observation-pool.old.tsv"
  matched="$APP_DIR/external-observation-matched.tmp"
  now="$(date '+%F %T')"
  source_label="external"
  [ -n "${CFST_ISP_PROFILE:-}" ] && source_label="external:${CFST_ISP_PROFILE}"
  [ -s "$EXTERNAL_OBSERVATION_POOL_FILE" ] && cp "$EXTERNAL_OBSERVATION_POOL_FILE" "$old" || printf 'ip\tbest_min_speed\tbest_avg_speed\trecent_min_speed\tpass_count\tfail_count\tconsecutive_passes\tconsecutive_fails\tfirst_seen\tlast_seen\tsource\tstatus\n' > "$old"

  awk -F '\t' '
    function ip2num(ip, parts) {
      split(ip, parts, ".")
      return (parts[1] * 16777216) + (parts[2] * 65536) + (parts[3] * 256) + parts[4]
    }
    function in_cidr(ip, cidr, bits, arr, mask) {
      if (cidr !~ /\//) return ip == cidr
      split(cidr, arr, "/")
      bits = arr[2] + 0
      if (bits < 0 || bits > 32) return 0
      mask = bits == 0 ? 0 : 4294967296 - (2 ^ (32 - bits))
      return and(ip2num(ip), mask) == and(ip2num(arr[1]), mask)
    }
    FNR == NR {
      if ($1 != "") external[++external_count]=$1
      next
    }
    FNR != NR {
      if (FNR == 1 || $1 == "") next
      ip=$1
      matched=0
      for (i=1; i<=external_count; i++) {
        if (in_cidr(ip, external[i])) {matched=1; break}
      }
      if (matched) print
    }
  ' "$external_file" "$STABILITY_RESULT_FILE" > "$matched"
  [ -s "$matched" ] || return 0

  awk -F '\t' \
    -v now="$now" \
    -v source_label="$source_label" \
    -v min_speed="${CFST_EXTERNAL_PROMOTION_MIN_SPEED:-0}" \
    -v rounds="${CFST_EXTERNAL_PROMOTION_ROUNDS:-3}" \
    -v evict="${CFST_EXTERNAL_OBSERVATION_EVICT_FAILS:-3}" '
    function clean(v) {
      gsub(/[\t\r\n[:cntrl:]]+/, "_", v)
      return v
    }
    function add_source(ip, s) {
      s = clean(s)
      if (source[ip] == "") source[ip] = s
      else if (source[ip] !~ "(^|,)" s "(,|$)") source[ip] = source[ip] "," s
    }
    FNR == NR {
      if (FNR > 1 && $1 != "") {
        ip=$1
        best_min[ip]=$2+0; best_avg[ip]=$3+0; recent[ip]=$4+0
        pass[ip]=$5+0; fail[ip]=$6+0; cpass[ip]=$7+0; cfail[ip]=$8+0
        first[ip]=$9; last[ip]=$10; source[ip]=clean($11); status[ip]=$12
        order[++order_count]=ip; seen[ip]=1
      }
      next
    }
    FNR != NR {
      if ($1 == "") next
      ip=$1
      min=$4+0; avg=$5+0; ok=$6+0
      good=(ok >= rounds && min >= min_speed)
      if (!(ip in seen)) {
        order[++order_count]=ip
        first[ip]=now; best_min[ip]=0; best_avg[ip]=0; recent[ip]=0
        pass[ip]=0; fail[ip]=0; cpass[ip]=0; cfail[ip]=0; seen[ip]=1
      }
      recent[ip]=min; last[ip]=now; add_source(ip, source_label)
      if (min > best_min[ip]) best_min[ip]=min
      if (avg > best_avg[ip]) best_avg[ip]=avg
      if (good) {
        pass[ip]++; cpass[ip]++; cfail[ip]=0
      } else {
        fail[ip]++; cfail[ip]++; cpass[ip]=0
      }
      if (cfail[ip] >= evict) status[ip]="degraded"
      else if (cpass[ip] >= rounds && min >= min_speed) status[ip]="eligible_manual_review"
      else status[ip]="observing"
    }
    END {
      print "ip\tbest_min_speed\tbest_avg_speed\trecent_min_speed\tpass_count\tfail_count\tconsecutive_passes\tconsecutive_fails\tfirst_seen\tlast_seen\tsource\tstatus"
      for (i=1; i<=order_count; i++) {
        ip=order[i]
        if (printed[ip]) continue
        printed[ip]=1
        print ip "\t" best_min[ip] "\t" best_avg[ip] "\t" recent[ip] "\t" pass[ip] "\t" fail[ip] "\t" cpass[ip] "\t" cfail[ip] "\t" first[ip] "\t" last[ip] "\t" clean(source[ip]) "\t" status[ip]
      }
    }
  ' "$old" "$matched" > "$tmp"
  mv "$tmp" "$EXTERNAL_OBSERVATION_POOL_FILE"
  log "外部观察池：已更新 $EXTERNAL_OBSERVATION_POOL_FILE；eligible 仅表示需要人工复核，不自动更新 DNS"
}

run_stability_retest() {
  rm -f "$STABILITY_RESULT_FILE"
  [ "${CFST_STABILITY_TEST_COUNT:-0}" -gt 0 ] 2>/dev/null || return 0
  [ "${CFST_STABILITY_TEST_ROUNDS:-0}" -gt 0 ] 2>/dev/null || return 0
  [ -n "$CFST_URL" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0

  local host
  host="$(cfst_url_host)"
  [ -n "$host" ] || return 0

  local candidate_file raw_file sorted_file
  candidate_file="$APP_DIR/stability-candidates.tsv"
  raw_file="$APP_DIR/stability-raw.tsv"
  sorted_file="$APP_DIR/stability-sorted.tsv"
  rm -f "$candidate_file" "$raw_file" "$sorted_file"

  build_stability_candidates > "$candidate_file"
  [ -s "$candidate_file" ] || return 0

  log "稳定性复测：对前 $(wc -l < "$candidate_file" | tr -d ' ') 个候选做 ${CFST_STABILITY_TEST_ROUNDS} 轮真实下载，地址 $CFST_URL"
  printf 'ip\tlatency_ms\tcfst_speed_mbps\tmin_speed_mbps\tavg_speed_mbps\tok_rounds\tsource\n' > "$STABILITY_RESULT_FILE"

  while IFS="$(printf '\t')" read -r ip latency cfst_speed source; do
    [ -n "$ip" ] || continue
    local round ok speed_bps
    round=1
    ok=0
    : > "$raw_file"
    while [ "$round" -le "$CFST_STABILITY_TEST_ROUNDS" ]; do
      speed_bps="$(download_speed_bps "$host" "$ip")"
      if [ -n "$speed_bps" ] && [ "$speed_bps" != "0" ]; then
        awk -v bps="$speed_bps" 'BEGIN {printf "%.2f\n", bps / 1048576}' >> "$raw_file"
        ok=$((ok + 1))
      else
        printf '0.00\n' >> "$raw_file"
      fi
      round=$((round + 1))
    done

    awk -v ip="$ip" -v latency="$latency" -v cfst_speed="$cfst_speed" -v ok="$ok" -v source="$source" '
      BEGIN {min = ""; sum = 0; count = 0}
      {
        speed = $1 + 0
        if (min == "" || speed < min) min = speed
        sum += speed
        count++
      }
      END {
        avg = count > 0 ? sum / count : 0
        printf "%s\t%s\t%s\t%.2f\t%.2f\t%d\t%s\n", ip, latency, cfst_speed, min + 0, avg, ok, source
      }
    ' "$raw_file" >> "$sorted_file"
  done < "$candidate_file"

  if [ -s "$sorted_file" ]; then
    {
      printf 'ip\tlatency_ms\tcfst_speed_mbps\tmin_speed_mbps\tavg_speed_mbps\tok_rounds\tsource\n'
      sort_stability_results < "$sorted_file" | apply_dual_pool_slots | promote_primary_safe_candidate | promote_stable_slots
    } > "$STABILITY_RESULT_FILE"
    if [ "${CFST_SKIP_POOL_UPDATE:-0}" != "1" ]; then
      update_champion_pool
      update_external_observation_pool
    fi
    log "稳定性复测：完成，已按留任挑战、冠军池、最低速度和平均速度重新排序"
  fi
}

selected_result_rows() {
  if [ -s "$STABILITY_RESULT_FILE" ]; then
    awk -F '\t' -v limit="$CFST_RESULT_COUNT" '
      NR == 1 {next}
      $1 != "" && count < limit {
        print $1 "\t" $2 "\t" $4
        count++
      }
    ' "$STABILITY_RESULT_FILE"
    return 0
  fi

  [ -s "$RESULT_FILE" ] || return 0
  awk -F, -v limit="$CFST_RESULT_COUNT" -v min_speed="${CFST_PREFER_MIN_SPEED:-0}" '
    NR == 1 {next}
    $1 != "" {
      ip=$1
      gsub(/[[:space:]]/, "", ip)
      row=ip "\t" $5 "\t" $6
      if (min_speed > 0 && ($6 + 0) >= min_speed) {
        preferred[++preferred_count]=row
      } else {
        fallback[++fallback_count]=row
      }
    }
    END {
      count=0
      for (i=1; i<=preferred_count && count<limit; i++) {
        print preferred[i]
        count++
      }
      for (i=1; i<=fallback_count && count<limit; i++) {
        print fallback[i]
        count++
      }
    }
  ' "$RESULT_FILE"
}

show_best_ips() {
  log "优选结果：前 $CFST_RESULT_COUNT 个 IP"
  selected_result_rows | awk -F '\t' '{printf "%d. %s  延迟:%s  速度:%s\n", NR, $1, $2, $3}' | tee -a "$LOG_FILE" "$INFORM_LOG"
}

best_ip_list() {
  selected_result_rows | awk -F '\t' '{print $1}'
}

record_type_for_ip() {
  case "$1" in
    *:*) echo AAAA ;;
    *) echo A ;;
  esac
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

delete_dns_records_by_name() {
  local name="$1"
  local api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"
  require_cloudflare_config
  [ -n "$name" ] || die "删除 DNS 记录时域名不能为空"

  log "DNS 清理：查询 $name 的 A/AAAA 记录"
  local response
  response="$(cf_api GET "$api?name=$name")"
  echo "$response" > "$APP_DIR/cf-delete-query.json"
  jq -e '.success == true' "$APP_DIR/cf-delete-query.json" >/dev/null || die "DNS 清理：查询失败"

  local count
  count="$(jq '[.result[] | select(.type=="A" or .type=="AAAA")] | length' "$APP_DIR/cf-delete-query.json")"
  if [ "$count" = "0" ]; then
    log "DNS 清理：未找到 $name 的 A/AAAA 记录"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1：将删除 $name 的 $count 条 A/AAAA 记录，但本次不真实删除"
    jq -r '.result[] | select(.type=="A" or .type=="AAAA") | "- \(.type) \(.name) -> \(.content)"' "$APP_DIR/cf-delete-query.json" | tee -a "$LOG_FILE"
    return 0
  fi

  jq -c '.result[] | select(.type=="A" or .type=="AAAA")' "$APP_DIR/cf-delete-query.json" | while IFS= read -r record; do
    local id rname rtype content delete_response
    id="$(echo "$record" | jq -r '.id')"
    rname="$(echo "$record" | jq -r '.name')"
    rtype="$(echo "$record" | jq -r '.type')"
    content="$(echo "$record" | jq -r '.content')"
    log "DNS 清理：删除 $rtype $rname -> $content"
    delete_response="$(cf_api DELETE "$api/$id")"
    if echo "$delete_response" | jq -e '.success == true' >/dev/null; then
      log "DNS 清理：删除成功"
    else
      log "DNS 清理：删除失败：$delete_response"
    fi
  done
}

create_dns_record() {
  local name="$1"
  local ip="$2"
  local api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"
  local record_type payload response
  record_type="$(record_type_for_ip "$ip")"
  payload="$(jq -cn \
    --arg type "$record_type" \
    --arg name "$name" \
    --arg content "$ip" \
    --argjson ttl "$CF_TTL" \
    --argjson proxied "$CF_PROXIED" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  if [ "$DRY_RUN" = "1" ]; then
    log "DRY_RUN=1：将创建 $record_type $name -> $ip"
    return 0
  fi

  log "DNS 更新：创建 $record_type $name -> $ip"
  response="$(cf_api POST "$api" "$payload")"
  if echo "$response" | jq -e '.success == true' >/dev/null; then
    inform "IP地址 $ip 成功解析到 $name"
  else
    inform "导入IP地址 $ip 到 $name 失败"
    log "DNS 更新失败响应：$response"
  fi
}

upsert_single_dns_record() {
  local name="$1"
  local ip="$2"
  local api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records"
  local record_type response record_id old_ip payload update_response
  record_type="$(record_type_for_ip "$ip")"

  log "DNS 更新：查询 $record_type $name"
  response="$(cf_api GET "$api?type=$record_type&name=$name")"
  echo "$response" > "$APP_DIR/cf-record-query.json"
  jq -e '.success == true' "$APP_DIR/cf-record-query.json" >/dev/null || die "Cloudflare DNS 查询失败"
  record_id="$(jq -r '.result[0].id // empty' "$APP_DIR/cf-record-query.json")"
  old_ip="$(jq -r '.result[0].content // empty' "$APP_DIR/cf-record-query.json")"

  payload="$(jq -cn \
    --arg type "$record_type" \
    --arg name "$name" \
    --arg content "$ip" \
    --argjson ttl "$CF_TTL" \
    --argjson proxied "$CF_PROXIED" \
    '{type:$type,name:$name,content:$content,ttl:$ttl,proxied:$proxied}')"

  if [ "$DRY_RUN" = "1" ]; then
    if [ -n "$record_id" ]; then
      log "DRY_RUN=1：将更新 $record_type $name：$old_ip -> $ip"
    else
      log "DRY_RUN=1：将创建 $record_type $name -> $ip"
    fi
    return 0
  fi

  if [ -n "$record_id" ]; then
    if [ "$old_ip" = "$ip" ]; then
      inform "$name 无需更新，当前已是 $ip"
      return 0
    fi
    log "DNS 更新：更新 $record_type $name：$old_ip -> $ip"
    update_response="$(cf_api PUT "$api/$record_id" "$payload")"
  else
    log "DNS 更新：创建 $record_type $name -> $ip"
    update_response="$(cf_api POST "$api" "$payload")"
  fi

  if echo "$update_response" | jq -e '.success == true' >/dev/null; then
    inform "$name 更新成功 -> $ip"
  else
    inform "$name 更新失败 -> $ip"
    log "DNS 更新失败响应：$update_response"
  fi
}

update_dns_multi_to_one() {
  [ -n "$CF_RECORD_NAME" ] || die "未配置完整解析域名 CF_RECORD_NAME"
  log "DNS 更新模式：多个优选 IP 解析到一个域名：$CF_RECORD_NAME"
  delete_dns_records_by_name "$CF_RECORD_NAME"
  best_ip_list | while IFS= read -r ip; do
    [ -n "$ip" ] && create_dns_record "$CF_RECORD_NAME" "$ip"
    sleep 1
  done
}

update_dns_one_to_one() {
  log "DNS 更新模式：每个优选 IP 解析到每个域名"
  [ -n "$CF_RECORD_NAMES" ] || die "每个优选 IP 解析到每个域名模式下，未配置 CF_RECORD_NAMES"
  local ip_tmp="$APP_DIR/best-ip-list.tmp"
  best_ip_list > "$ip_tmp"
  local i=1
  for name in $CF_RECORD_NAMES; do
    local ip
    ip="$(sed -n "${i}p" "$ip_tmp")"
    if [ -z "$ip" ]; then
      log "DNS 更新：域名 $name 没有对应 IP，跳过"
      i=$((i + 1))
      continue
    fi
    upsert_single_dns_record "$name" "$ip"
    i=$((i + 1))
    sleep 1
  done
}

update_cloudflare() {
  if [ "$PUSH_MODE" != "domain" ]; then
    log "推送模式：IP 直接输出，不更新 Cloudflare DNS"
    inform "优选IP排名如下"
    best_ip_list | tee -a "$INFORM_LOG"
    return 0
  fi
  if [ "${CFST_EXTERNAL_CANDIDATES:-0}" = "1" ] && [ "${CFST_EXTERNAL_CANDIDATES_ALLOW_DNS:-0}" != "1" ]; then
    die "外部候选源实验默认不允许更新 Cloudflare DNS"
  fi

  check_cloudflare_auth
  if [ "$DOMAIN_UPDATE_MODE" = "one_to_one" ]; then
    update_dns_one_to_one
  else
    update_dns_multi_to_one
  fi
}

identify_reverse_ip_regions() {
  [ "$CDN_IP_MODE" = "reverse" ] || return 0
  log "反代 IP：开始识别前 10 个优选 IP 的国家/地区"
  echo "" >> "$INFORM_LOG"
  echo "优选反代IP--国家地区识别" >> "$INFORM_LOG"
  best_ip_list | head -n 10 | while IFS= read -r ip; do
    [ -n "$ip" ] || continue
    country=""
    country="$(curl -sm5 --user-agent "Mozilla/5.0" "https://api.ip.sb/geoip/$ip" -k | jq -r '.country_code // empty' 2>/dev/null || true)"
    [ -n "$country" ] || country="未知"
    echo "IP地址 $ip 的地区是: $country" | tee -a "$LOG_FILE" "$INFORM_LOG"
    sleep 1
  done
}

send_notifications() {
  local message
  [ -f "$INFORM_LOG" ] || return 0
  message="$(cat "$INFORM_LOG")"

  if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_USER_ID" ]; then
    log "通知：发送 Telegram 推送"
    if timeout 20 curl -s -X POST "https://${TELEGRAM_API}/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -d "chat_id=${TELEGRAM_USER_ID}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${message}" >/tmp/cf-dns-speedup-tg.json; then
      if jq -e '.ok == true' /tmp/cf-dns-speedup-tg.json >/dev/null 2>&1; then
        log "通知：Telegram 推送成功"
      else
        log "通知：Telegram 推送失败"
      fi
    else
      log "通知：Telegram 请求超时或失败"
    fi
  else
    log "通知：未配置 Telegram"
  fi

  if [ -n "$PUSHPLUS_TOKEN" ]; then
    log "通知：发送 PushPlus 推送"
    if timeout 20 curl -s -X POST "http://www.pushplus.plus/send" \
      -d "token=${PUSHPLUS_TOKEN}" \
      -d "title=Cloudflare优选IP推送通知" \
      -d "template=html" \
      --data-urlencode "content=${message}" >/tmp/cf-dns-speedup-pushplus.json; then
      if jq -e '.code == 200' /tmp/cf-dns-speedup-pushplus.json >/dev/null 2>&1; then
        log "通知：PushPlus 推送成功"
      else
        log "通知：PushPlus 推送失败"
      fi
    else
      log "通知：PushPlus 请求超时或失败"
    fi
  else
    log "通知：未配置 PushPlus"
  fi
}

run_once() {
  acquire_lock
  rotate_logs
  RUN_STARTED_AT="$(date '+%F %T')"
  RUN_STATUS="running"
  RUN_ERROR=""
  : > "$INFORM_LOG"
  log "------------------------------------------------------------"
  log "Cloudflare 优选 IP 自动更新脚本（安全修正版）开始执行"
  log "推送模式：$PUSH_MODE；解析方案：$DOMAIN_UPDATE_MODE；IP 来源：$CDN_IP_MODE；DRY_RUN=$DRY_RUN"
  prepare_assets
  stop_proxy_if_needed
  run_speedtest
  restart_proxy_if_needed
  show_best_ips
  identify_reverse_ip_regions
  update_cloudflare
  send_notifications
  RUN_STATUS="success"
  log "执行完成。定时任务示例：30 6 * * * cd /root/cf-dns-speedup && /usr/bin/env bash ./cf-dns-speedup.sh >/tmp/cf-dns-speedup.cron.log 2>&1"
}

delete_records_command() {
  local name="${DELETE_RECORD_NAME:-$CF_RECORD_NAME}"
  require_cloudflare_config
  delete_dns_records_by_name "$name"
}

print_service_health() {
  /etc/init.d/passwall enabled >/dev/null 2>&1 && echo "passwall_enabled=yes" || echo "passwall_enabled=no"
  /etc/init.d/smartdns status 2>/dev/null || true
  /etc/init.d/dnsmasq status 2>/dev/null || true
  /etc/init.d/firewall status 2>/dev/null || true
}

print_dns_health() {
  [ -n "$CF_RECORD_NAMES" ] || return 0
  for name in $CF_RECORD_NAMES; do
    if command -v nslookup >/dev/null 2>&1; then
      nslookup "$name" 127.0.0.1 2>/dev/null | awk -v name="$name" '
        /^Address [0-9]+: / && $3 !~ /^(127\.|::1)/ {ip=$3}
        /^Address: / && $2 !~ /^(127\.|::1)/ {ip=$2}
        END {if (ip != "") print name " router_dns " ip; else print name " router_dns unresolved"}
      '
    fi
    if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ] && command -v jq >/dev/null 2>&1; then
      local api response
      api="https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/dns_records?type=A&name=$name"
      response="$(cf_api GET "$api" 2>/dev/null || true)"
      if echo "$response" | jq -e '.success == true' >/dev/null 2>&1; then
        echo "$response" | jq -r --arg name "$name" '.result[0] | "\($name) cloudflare_api \(.content // "missing") ttl=\(.ttl // "n/a") proxied=\(.proxied | tostring)"'
      else
        echo "$name cloudflare_api unavailable"
      fi
    fi
  done
}

health_check_command() {
  mkdir -p "$APP_DIR"
  {
    echo "=== health-check ==="
    date
    echo
    echo "=== config ==="
    printf 'PUSH_MODE=%s\n' "$PUSH_MODE"
    printf 'DOMAIN_UPDATE_MODE=%s\n' "$DOMAIN_UPDATE_MODE"
    printf 'CFST_DOWNLOAD_COUNT=%s\n' "$CFST_DOWNLOAD_COUNT"
    printf 'CFST_DOWNLOAD_COUNT_STEP=%s\n' "$CFST_DOWNLOAD_COUNT_STEP"
    printf 'CFST_DOWNLOAD_COUNT_MAX=%s\n' "$CFST_DOWNLOAD_COUNT_MAX"
    printf 'CFST_RESULT_COUNT=%s\n' "$CFST_RESULT_COUNT"
    printf 'CFST_PREFER_MIN_SPEED=%s\n' "$CFST_PREFER_MIN_SPEED"
    printf 'CFST_STABILITY_TEST_COUNT=%s\n' "$CFST_STABILITY_TEST_COUNT"
    printf 'CFST_STABILITY_TEST_ROUNDS=%s\n' "$CFST_STABILITY_TEST_ROUNDS"
    printf 'CFST_RETAIN_MIN_SPEED=%s\n' "$CFST_RETAIN_MIN_SPEED"
    printf 'CFST_DEGRADE_MIN_SPEED=%s\n' "$CFST_DEGRADE_MIN_SPEED"
    printf 'CFST_URL=%s\n' "$CFST_URL"
    printf 'PROXY_PLUGIN=%s\n' "$PROXY_PLUGIN"
    printf 'DRY_RUN=%s\n' "$DRY_RUN"
    echo
    echo "=== files ==="
    ls -l "$RESULT_FILE" "$STABILITY_RESULT_FILE" "$LAST_RUN_SUMMARY" 2>/dev/null || true
    echo
    echo "=== selected ==="
    selected_result_rows 2>/dev/null | head -n "$CFST_RESULT_COUNT" || true
    echo
    echo "=== stability ==="
    cat "$STABILITY_RESULT_FILE" 2>/dev/null || true
    echo
    echo "=== summary ==="
    cat "$LAST_RUN_SUMMARY" 2>/dev/null || true
    echo
    echo "=== lock ==="
    ls -ld "$LOCK_DIR" 2>/dev/null || echo "no_lock"
    [ -f "$LOCK_DIR/pid" ] && cat "$LOCK_DIR/pid" 2>/dev/null || true
    echo
    echo "=== cron ==="
    crontab -l 2>/dev/null | grep -n 'cf-dns-speedup\|DISABLED_BY_CODEX' || true
    echo
    echo "=== dns ==="
    print_dns_health
    echo
    echo "=== services ==="
    print_service_health
  } | tee "$HEALTH_REPORT_FILE"
}

validate_current_impl() {
  [ -n "$CFST_URL" ] || die "CFST_URL is empty; cannot validate current IPs"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  local host
  host="$(cfst_url_host)"
  [ -n "$host" ] || die "cannot parse host from CFST_URL"

  local candidates
  candidates="$APP_DIR/validate-current.candidates.tsv"
  current_dns_candidate_rows | awk -F '\t' '{print $1 "\t" ($2 + 0) "\t" ($3 + 0)}' | head -n "$CFST_RESULT_COUNT" > "$candidates"
  if [ ! -s "$candidates" ]; then
    selected_result_rows | head -n "$CFST_RESULT_COUNT" > "$candidates"
  fi
  [ -s "$candidates" ] || die "no selected IPs to validate"

  printf 'ip\tprevious_latency_ms\tprevious_speed_mbps\tmin_speed_mbps\tavg_speed_mbps\tok_rounds\n' > "$VALIDATE_RESULT_FILE"
  while IFS="$(printf '\t')" read -r ip latency previous_speed; do
    [ -n "$ip" ] || continue
    local round ok raw_file speed_bps
    raw_file="$APP_DIR/validate-current.raw"
    : > "$raw_file"
    round=1
    ok=0
    while [ "$round" -le "$VALIDATE_CURRENT_ROUNDS" ]; do
      speed_bps="$(download_speed_bps "$host" "$ip")"
      if [ -n "$speed_bps" ] && [ "$speed_bps" != "0" ]; then
        awk -v bps="$speed_bps" 'BEGIN {printf "%.2f\n", bps / 1048576}' >> "$raw_file"
        ok=$((ok + 1))
      else
        printf '0.00\n' >> "$raw_file"
      fi
      round=$((round + 1))
    done
    awk -v ip="$ip" -v latency="$latency" -v previous_speed="$previous_speed" -v ok="$ok" '
      BEGIN {min = ""; sum = 0; count = 0}
      {
        speed = $1 + 0
        if (min == "" || speed < min) min = speed
        sum += speed
        count++
      }
      END {
        avg = count > 0 ? sum / count : 0
        printf "%s\t%s\t%s\t%.2f\t%.2f\t%d\n", ip, latency, previous_speed, min + 0, avg, ok
      }
    ' "$raw_file" >> "$VALIDATE_RESULT_FILE"
  done < "$candidates"

  cat "$VALIDATE_RESULT_FILE"
}

validate_current_command() {
  acquire_lock
  validate_current_impl
}

observe_current_command() {
  acquire_lock
  local ts
  ts="$(date '+%F %T')"

  validate_current_impl

  if [ ! -s "$OBSERVATION_HISTORY_FILE" ]; then
    printf 'observed_at\tip\tprevious_latency_ms\tprevious_speed_mbps\tmin_speed_mbps\tavg_speed_mbps\tok_rounds\n' > "$OBSERVATION_HISTORY_FILE"
  fi
  awk -F '\t' -v ts="$ts" 'NR > 1 && $1 != "" {print ts "\t" $0}' "$VALIDATE_RESULT_FILE" >> "$OBSERVATION_HISTORY_FILE"

  echo
  echo "=== dns ==="
  print_dns_health
  echo
  echo "=== services ==="
  print_service_health
  echo
  printf 'observation_history=%s\n' "$OBSERVATION_HISTORY_FILE"
}

install_observe_cron_command() {
  local schedule line tmp
  schedule="$CFST_OBSERVE_CRON"
  line="$schedule cd $APP_DIR && /usr/bin/env bash ./cf-dns-speedup.sh observe-current >>/tmp/cf-dns-speedup.observe.log 2>&1"
  tmp="/tmp/cf-dns-speedup-cron.$$"
  crontab -l 2>/dev/null | grep -v 'cf-dns-speedup.sh observe-current' > "$tmp" || true
  printf '%s\n' "$line" >> "$tmp"
  crontab "$tmp"
  rm -f "$tmp"
  printf 'installed_observe_cron=%s\n' "$line"
}

current_observation_report_command() {
  [ -s "$OBSERVATION_HISTORY_FILE" ] || die "observation history is empty: $OBSERVATION_HISTORY_FILE"
  local generated_at
  generated_at="$(date '+%F %T')"
  {
    echo "=== current-observation-report ==="
    printf 'generated_at=%s\n' "$generated_at"
    printf 'history_file=%s\n' "$OBSERVATION_HISTORY_FILE"
    printf 'min_speed_threshold=%s MB/s\n' "$CFST_OBSERVE_MIN_SPEED"
    echo
    echo "=== dns ==="
    print_dns_health
    echo
    echo "=== summary_by_ip ==="
    awk -F '\t' -v threshold="${CFST_OBSERVE_MIN_SPEED:-8}" '
      NR == 1 {next}
      $1 != "" && $2 != "" {
        ip=$2
        min=$5+0
        avg=$6+0
        ok=$7+0
        count[ip]++
        if (!(ip in seen)) {
          first[ip]=$1
          min_seen[ip]=min
          max_seen[ip]=min
          seen_order[++n]=ip
          seen[ip]=1
        }
        last[ip]=$1
        if (min < min_seen[ip]) min_seen[ip]=min
        if (min > max_seen[ip]) max_seen[ip]=min
        sum_min[ip]+=min
        sum_avg[ip]+=avg
        if (min < threshold || ok < 1) low[ip]++
      }
      END {
        print "ip\tobservations\tmin_of_min\tavg_of_min\tavg_speed\tlow_count\tstatus\tfirst_seen\tlast_seen"
        for (i=1; i<=n; i++) {
          ip=seen_order[i]
          avg_min=count[ip] ? sum_min[ip]/count[ip] : 0
          avg_speed=count[ip] ? sum_avg[ip]/count[ip] : 0
          status="active"
          if (low[ip] >= 3) status="stale"
          else if (low[ip] >= 1) status="watch"
          printf "%s\t%d\t%.2f\t%.2f\t%.2f\t%d\t%s\t%s\t%s\n", ip, count[ip], min_seen[ip], avg_min, avg_speed, low[ip]+0, status, first[ip], last[ip]
        }
      }
    ' "$OBSERVATION_HISTORY_FILE"
    echo
    echo "=== recent_observations ==="
    tail -n 20 "$OBSERVATION_HISTORY_FILE"
  } | tee "$CURRENT_OBSERVATION_REPORT_FILE"
}

external_candidate_check_command() {
  mkdir -p "$APP_DIR"
  : > "$EXTERNAL_CANDIDATE_CHECK_FILE"
  prepare_external_candidates_to_file "$EXTERNAL_CANDIDATE_CHECK_FILE"
  {
    echo "=== external-candidate-check ==="
    date
    echo
    echo "=== config ==="
    printf 'CFST_EXTERNAL_CANDIDATES=%s\n' "$CFST_EXTERNAL_CANDIDATES"
    printf 'CFST_ISP_PROFILE=%s\n' "$CFST_ISP_PROFILE"
    printf 'CFST_EXTERNAL_CANDIDATE_URL_LIMIT=%s\n' "$CFST_EXTERNAL_CANDIDATE_URL_LIMIT"
    printf 'CFST_EXTERNAL_CANDIDATE_LIMIT=%s\n' "$CFST_EXTERNAL_CANDIDATE_LIMIT"
    printf 'CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT=%s\n' "$CFST_EXTERNAL_CANDIDATE_SOURCE_LIMIT"
    printf 'CFST_EXTERNAL_CANDIDATE_ALLOWED_HOSTS=%s\n' "$CFST_EXTERNAL_CANDIDATE_ALLOWED_HOSTS"
    printf 'IP_VERSION=%s\n' "$IP_VERSION"
    echo
    echo "=== report ==="
    cat "$EXTERNAL_CANDIDATE_REPORT_FILE" 2>/dev/null || true
    echo
    echo "=== candidates ==="
    printf 'accepted_count=%s\n' "$(wc -l < "$EXTERNAL_CANDIDATE_CHECK_FILE" 2>/dev/null | tr -d ' ')"
    head -n 30 "$EXTERNAL_CANDIDATE_CHECK_FILE" 2>/dev/null || true
  }
}

stability_verify_command() {
  acquire_lock
  rotate_logs
  RUN_STARTED_AT="$(date '+%F %T')"
  RUN_STATUS="running"
  RUN_ERROR=""
  [ -s "$RESULT_FILE" ] || die "result.csv missing; cannot run stability verification"
  CFST_SKIP_POOL_UPDATE=1
  STABILITY_RESULT_FILE="$STABILITY_VERIFY_RESULT_FILE"
  log "稳定性验证：复用现有 result.csv，只复测候选并重排；不停止代理、不更新 DNS、不发送通知"
  run_stability_retest
  [ -s "$STABILITY_RESULT_FILE" ] || die "stability verification did not produce results"
  show_best_ips
  RUN_STATUS="success"
  log "稳定性验证完成；如结果满意，可再执行 stability-update 或 run 进行实际更新"
}

stability_update_command() {
  acquire_lock
  rotate_logs
  RUN_STARTED_AT="$(date '+%F %T')"
  RUN_STATUS="running"
  RUN_ERROR=""
  : > "$INFORM_LOG"
  [ -s "$RESULT_FILE" ] || die "result.csv 不存在，无法只执行稳定性复测"
  log "------------------------------------------------------------"
  log "稳定性复测更新：复用现有 result.csv，不重新执行 cfst 粗筛"
  stop_proxy_if_needed
  run_stability_retest
  restart_proxy_if_needed
  [ -s "$STABILITY_RESULT_FILE" ] || die "稳定性复测未生成结果"
  show_best_ips
  identify_reverse_ip_regions
  update_cloudflare
  send_notifications
  RUN_STATUS="success"
  log "稳定性复测更新完成"
}

external_observe_command() {
  PUSH_MODE="ip"
  DRY_RUN=1
  PROXY_PLUGIN=0
  CFST_CHAMPION_POOL=0
  CFST_EXTERNAL_CANDIDATES=1
  CFST_EXTERNAL_OBSERVATION_POOL=1
  CFST_EXTERNAL_CANDIDATES_ALLOW_DNS=0
  CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION=0
  if [ -z "${CFST_ISP_PROFILE:-}" ] && [ -z "${CFST_EXTERNAL_CANDIDATE_URLS:-}" ]; then
    CFST_ISP_PROFILE="cf"
  fi
  log "外部观察：强制 DRY_RUN=1、PUSH_MODE=ip、PROXY_PLUGIN=0、CFST_CHAMPION_POOL=0，不更新 DNS，不写冠军池"
  run_once
}

observation_report_command() {
  if [ ! -s "$EXTERNAL_OBSERVATION_POOL_FILE" ]; then
    echo "external observation pool is empty: $EXTERNAL_OBSERVATION_POOL_FILE"
    return 0
  fi
  {
    echo "=== external-observation-report ==="
    date
    echo
    echo "=== config ==="
    printf 'pool_file=%s\n' "$EXTERNAL_OBSERVATION_POOL_FILE"
    printf 'promotion_rounds=%s\n' "$CFST_EXTERNAL_PROMOTION_ROUNDS"
    printf 'promotion_min_speed=%s\n' "$CFST_EXTERNAL_PROMOTION_MIN_SPEED"
    printf 'evict_fails=%s\n' "$CFST_EXTERNAL_OBSERVATION_EVICT_FAILS"
    echo
    echo "=== eligible_manual_review ==="
    awk -F '\t' 'NR == 1 || $12 == "eligible_manual_review" {print}' "$EXTERNAL_OBSERVATION_POOL_FILE"
    echo
    echo "=== recent ranking ==="
    awk -F '\t' '
      NR == 1 {next}
      $1 != "" {
        line[++n]=$0
        recent[n]=$4+0
        cpass[n]=$7+0
        best[n]=$2+0
      }
      END {
        for (i=1; i<=n; i++) {
          pick=i
          for (j=i+1; j<=n; j++) {
            if (recent[j] > recent[pick] || (recent[j] == recent[pick] && cpass[j] > cpass[pick]) || (recent[j] == recent[pick] && cpass[j] == cpass[pick] && best[j] > best[pick])) pick=j
          }
          tmp=line[i]; line[i]=line[pick]; line[pick]=tmp
          tmp=recent[i]; recent[i]=recent[pick]; recent[pick]=tmp
          tmp=cpass[i]; cpass[i]=cpass[pick]; cpass[pick]=tmp
          tmp=best[i]; best[i]=best[pick]; best[pick]=tmp
          if (i <= 20) print line[i]
        }
      }
    ' "$EXTERNAL_OBSERVATION_POOL_FILE"
  }
}


main() {
  load_config
  source_optional_lib "$APP_DIR/lib/champion-pool.sh"
  need_cmd curl
  case "${1:-run}" in
    external-candidate-check)
      need_cmd awk
      need_cmd sed
      external_candidate_check_command
      return
      ;;
  esac
  install_deps_openwrt
  need_cmd jq
  need_cmd timeout
  need_cmd unzip
  trap cleanup_on_exit EXIT

  case "${1:-run}" in
    run) run_once ;;
    health-check) health_check_command ;;
    validate-current) validate_current_command ;;
    observe-current) observe_current_command ;;
    current-observation-report) current_observation_report_command ;;
    champion-report) champion_report_command ;;
    install-observe-cron) install_observe_cron_command ;;
    external-candidate-check) external_candidate_check_command ;;
    external-observe) external_observe_command ;;
    observation-report) observation_report_command ;;
    stability-update) stability_update_command ;;
    stability-verify) stability_verify_command ;;
    delete-records) delete_records_command ;;
    *) die "未知命令：$1" ;;
  esac
}

main "$@"
