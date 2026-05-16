#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
CONFIG_FILE="${CONFIG_FILE:-$APP_DIR/config.env}"
CFST_BIN="${CFST_BIN:-$APP_DIR/cfst}"
IP_FILE="${IP_FILE:-$APP_DIR/ip.txt}"
RESULT_FILE="${RESULT_FILE:-$APP_DIR/result.csv}"
LOG_FILE="${LOG_FILE:-$APP_DIR/run.log}"
INFORM_LOG="${INFORM_LOG:-$APP_DIR/informlog}"

CFST_SOURCE_BASE="${CFST_SOURCE_BASE:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3}"
DEFAULT_IPV4_LIST="${DEFAULT_IPV4_LIST:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3/ip.txt}"
DEFAULT_IPV6_LIST="${DEFAULT_IPV6_LIST:-https://gitlab.com/rwkgyg/CFwarp/-/raw/main/point/cpu3/ipv6.txt}"
REVERSE_ZIP_PRIMARY="${REVERSE_ZIP_PRIMARY:-https://zip.baipiao.eu.org}"
REVERSE_ZIP_FALLBACK="${REVERSE_ZIP_FALLBACK:-https://cf.yg-kkk.gq}"

PROXY_STOPPED=0
PROXY_SERVICE=""

log() {
  mkdir -p "$APP_DIR"
  printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

inform() {
  mkdir -p "$APP_DIR"
  printf '%s\n' "$*" | tee -a "$INFORM_LOG"
}

die() {
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
  CFST_TIMEOUT="${CFST_TIMEOUT:-4}"
  CFST_TOTAL_TIMEOUT="${CFST_TOTAL_TIMEOUT:-900}"
  CFST_DOWNLOAD_TIMEOUT="${CFST_DOWNLOAD_TIMEOUT:-8}"
  CFST_MIN_SPEED="${CFST_MIN_SPEED:-0}"
  CFST_MAX_LATENCY="${CFST_MAX_LATENCY:-9999}"
  CFST_MIN_LATENCY="${CFST_MIN_LATENCY:-0}"
  CFST_URL="${CFST_URL:-}"
  IP_VERSION="${IP_VERSION:-ipv4}"
  DRY_RUN="${DRY_RUN:-1}"
  PROXY_PLUGIN="${PROXY_PLUGIN:-0}"
  PROXY_RESTART_WAIT="${PROXY_RESTART_WAIT:-30}"
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
  TELEGRAM_USER_ID="${TELEGRAM_USER_ID:-}"
  TELEGRAM_API="${TELEGRAM_API:-api.telegram.org}"
  PUSHPLUS_TOKEN="${PUSHPLUS_TOKEN:-}"
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

prepare_assets() {
  mkdir -p "$APP_DIR"
  prepare_cfst
  if [ "$CDN_IP_MODE" = "reverse" ]; then
    prepare_reverse_ip_list
  else
    prepare_official_ip_list
  fi
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
  restart_proxy_if_needed || true
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
  rm -f "$RESULT_FILE"
  local args
  args="-tp $CFST_PORT -t $CFST_TIMEOUT -n $CFST_THREADS -dn $CFST_COUNT -p $CFST_COUNT -tl $CFST_MAX_LATENCY -tll $CFST_MIN_LATENCY -sl $CFST_MIN_SPEED -dt $CFST_DOWNLOAD_TIMEOUT -f $IP_FILE -o $RESULT_FILE"
  if [ -n "$CFST_URL" ]; then
    args="$args -url $CFST_URL"
    log "测速：已开启下载测速，地址 $CFST_URL"
  else
    args="$args -dd"
    log "测速：未开启下载测速，仅做延迟优选"
  fi

  log "测速：端口 $CFST_PORT，线程 $CFST_THREADS，显示数量 $CFST_COUNT，总超时 ${CFST_TOTAL_TIMEOUT}s"
  log "测速：下面显示 cfst 实时进度和速度；主日志只记录关键步骤，避免进度刷屏"
  local cfst_raw_log="$APP_DIR/cfst-output.log"
  rm -f "$cfst_raw_log"
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

show_best_ips() {
  log "优选结果：前 $CFST_COUNT 个 IP"
  awk -F, 'NR==1 {next} NR>1 && $1 != "" {gsub(/[[:space:]]/, "", $1); printf "%d. %s  延迟:%s  速度:%s\n", NR-1, $1, $5, $6}' "$RESULT_FILE" | head -n "$CFST_COUNT" | tee -a "$LOG_FILE" "$INFORM_LOG"
}

best_ip_list() {
  awk -F, 'NR>1 && $1 != "" {gsub(/[[:space:]]/, "", $1); print $1}' "$RESULT_FILE" | head -n "$CFST_COUNT"
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
  log "执行完成。定时任务示例：30 6 * * * cd /root/cf-dns-speedup && /usr/bin/env bash ./cf-dns-speedup.sh >/tmp/cf-dns-speedup.cron.log 2>&1"
}

delete_records_command() {
  local name="${DELETE_RECORD_NAME:-$CF_RECORD_NAME}"
  require_cloudflare_config
  delete_dns_records_by_name "$name"
}

main() {
  load_config
  need_cmd curl
  install_deps_openwrt
  need_cmd jq
  need_cmd timeout
  need_cmd unzip
  trap cleanup_on_exit EXIT

  case "${1:-run}" in
    run) run_once ;;
    delete-records) delete_records_command ;;
    *) die "未知命令：$1" ;;
  esac
}

main "$@"
