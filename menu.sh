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

set_raw() {
  key="$1"
  value="$2"
  if grep -qE "^${key}=" "$CONFIG_FILE"; then
    sed -i "s/^${key}=.*/${key}=${value}/" "$CONFIG_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$CONFIG_FILE"
  fi
}

pause() {
  printf '\n按回车继续...'
  read -r _
}

mask_token() {
  token="$1"
  [ -n "$token" ] || { echo ""; return; }
  case "$token" in
    put_your*) echo "$token" ;;
    "") echo "" ;;
    *) echo "********" ;;
  esac
}

plugin_name() {
  case "$1" in
    1) echo Passwall ;;
    2) echo Passwall2 ;;
    3) echo SSR-Plus ;;
    4) echo Clash ;;
    5) echo OpenClash ;;
    6) echo Bypass ;;
    7) echo V2raya ;;
    8) echo Hello-World ;;
    9) echo Homeproxy ;;
    10) echo MihomoTProxy ;;
    11) echo ShellCrash ;;
    *) echo "不使用任何插件" ;;
  esac
}

print_status() {
  ensure_config
  echo
  echo "当前配置："
  [ "$(get_value PUSH_MODE)" = "domain" ] && echo "- 推送模式：域名解析推送（需要域名，推荐）" || echo "- 推送模式：IP 直接推送（无需域名）"
  [ "$(get_value CDN_IP_MODE)" = "reverse" ] && echo "- IP 来源：CDN 反代 IP" || echo "- IP 来源：Cloudflare CDN 官方 IP"
  if [ "$(get_value DOMAIN_UPDATE_MODE)" = "one_to_one" ]; then
    echo "- 解析方案：每个优选 IP 解析到每个域名"
  else
    echo "- 解析方案：多个优选 IP 解析到一个域名"
  fi
  echo "- 优选类型：$(get_value IP_VERSION)"
  echo "- 使用端口：$(get_value CFST_PORT)"
  if [ -n "$(get_value CFST_URL)" ]; then
    echo "- 下载测速：已开启，地址：$(get_value CFST_URL)"
  else
    echo "- 下载测速：已关闭，只做延迟优选"
  fi
  echo "- 代理插件：$(plugin_name "$(get_value PROXY_PLUGIN)")"
  echo "- 代理重启等待：$(get_value PROXY_RESTART_WAIT) 秒"
  echo "- cfst 总超时：$(get_value CFST_TOTAL_TIMEOUT) 秒"
  echo "- cfst 单 IP 超时：$(get_value CFST_TIMEOUT) 秒；下载超时：$(get_value CFST_DOWNLOAD_TIMEOUT) 秒"
  echo "- 延迟范围：$(get_value CFST_MIN_LATENCY)-$(get_value CFST_MAX_LATENCY) ms；下载速度下限：$(get_value CFST_MIN_SPEED) MB/s"
  echo "- multi 域名：$(get_value CF_RECORD_NAME)"
  echo "- one_to_one 域名列表：$(get_value CF_RECORD_NAMES)"
  echo "- Cloudflare Zone ID：$(get_value CF_ZONE_ID)"
  echo "- Cloudflare API Token：$(mask_token "$(get_value CF_API_TOKEN)")"
  if [ -n "$(get_value TELEGRAM_BOT_TOKEN)" ]; then
    echo "- Telegram：已配置"
  else
    echo "- Telegram：未配置"
  fi
  echo "- Telegram API：$(get_value TELEGRAM_API)"
  if [ -n "$(get_value PUSHPLUS_TOKEN)" ]; then
    echo "- PushPlus：已配置"
  else
    echo "- PushPlus：未配置"
  fi
  echo "- DRY_RUN：$(get_value DRY_RUN)"
  echo "- 测速线程/下载测速数量/显示数量：$(get_value CFST_THREADS)/$(get_value CFST_DOWNLOAD_COUNT)/$(get_value CFST_RESULT_COUNT)"
}

configure_cloudflare() {
  ensure_config
  echo
  echo "配置 Cloudflare 信息"
  printf "请输入 Cloudflare API Token（建议 Zone:Read + DNS:Edit 最小权限，回车保持不变）: "
  read -r token
  [ -n "$token" ] && set_value CF_API_TOKEN "$token"
  printf "请输入 Cloudflare 区域 ID Zone ID（回车保持不变）: "
  read -r zone
  [ -n "$zone" ] && set_value CF_ZONE_ID "$zone"
  printf "是否开启 Cloudflare 小云朵代理 true/false（默认 false）: "
  read -r proxied
  [ -n "$proxied" ] || proxied=false
  set_raw CF_PROXIED "$proxied"
  echo "Cloudflare 信息已保存。"
}

configure_speed_url() {
  ensure_config
  echo
  echo "是否测速？"
  echo "1. 开启下载测速"
  echo "2. 关闭下载测速，只做延迟优选"
  printf "请选择（回车默认 2）: "
  read -r choice
  if [ "$choice" = "1" ]; then
    printf "请输入测速地址，需包含 http(s)://，例如 https://speed.cloudflare.com/__down?bytes=104857600: "
    read -r url
    [ -n "$url" ] || url="https://speed.cloudflare.com/__down?bytes=104857600"
    set_value CFST_URL "$url"
  else
    set_value CFST_URL ""
  fi
  echo "测速设置已保存。"
}

configure_port() {
  ensure_config
  echo
  echo "开启 TLS 常用端口：443、8443、2053、2083、2087、2096"
  echo "关闭 TLS 常用端口：80、8080、8880、2052、2082、2086、2095"
  printf "请选择端口（回车默认 443）: "
  read -r port
  [ -n "$port" ] || port=443
  set_raw CFST_PORT "$port"
  echo "端口已保存。"
}

configure_ip_version() {
  ensure_config
  echo
  echo "1. 优选 IPv4"
  echo "2. 优选 IPv6"
  printf "请选择（回车默认 IPv4）: "
  read -r choice
  if [ "$choice" = "2" ]; then
    set_value IP_VERSION "ipv6"
  else
    set_value IP_VERSION "ipv4"
  fi
  echo "IP 类型已保存。"
}

configure_threads() {
  ensure_config
  echo
  printf "请输入测速线程数量（OpenWrt 推荐 16-32，默认 32）: "
  read -r threads
  [ -n "$threads" ] || threads=32
  set_raw CFST_THREADS "$threads"
  printf "请输入旧版兼容显示数量 CFST_COUNT（默认 5）: "
  read -r count
  [ -n "$count" ] || count=5
  set_raw CFST_COUNT "$count"
  printf "请输入参与下载测速的候选 IP 数量 CFST_DOWNLOAD_COUNT（4K 推荐 100，均衡推荐 50）: "
  read -r download_count
  [ -n "$download_count" ] || download_count=100
  set_raw CFST_DOWNLOAD_COUNT "$download_count"
  printf "请输入最终显示/更新 DNS 的 IP 数量 CFST_RESULT_COUNT（默认 5）: "
  read -r result_count
  [ -n "$result_count" ] || result_count=5
  set_raw CFST_RESULT_COUNT "$result_count"
  printf "请输入 cfst 总超时秒数（dn=100 推荐 3600；20MB 推荐 4200）: "
  read -r total_timeout
  [ -n "$total_timeout" ] || total_timeout=3600
  set_raw CFST_TOTAL_TIMEOUT "$total_timeout"
  printf "请输入单个 IP 延迟测试超时秒数（默认 4）: "
  read -r timeout
  [ -n "$timeout" ] || timeout=4
  set_raw CFST_TIMEOUT "$timeout"
  printf "请输入下载测速超时秒数（dn=100 推荐 25；20MB 推荐 30）: "
  read -r download_timeout
  [ -n "$download_timeout" ] || download_timeout=25
  set_raw CFST_DOWNLOAD_TIMEOUT "$download_timeout"
  printf "请输入平均延迟下限 ms（默认 0，一般不用过滤）: "
  read -r min_latency
  [ -n "$min_latency" ] || min_latency=0
  set_raw CFST_MIN_LATENCY "$min_latency"
  printf "请输入平均延迟上限 ms（默认 300；想不限制可填 9999）: "
  read -r max_latency
  [ -n "$max_latency" ] || max_latency=300
  set_raw CFST_MAX_LATENCY "$max_latency"
  printf "请输入下载速度下限 MB/s（默认 0；确认测速正常后可填 1）: "
  read -r min_speed
  [ -n "$min_speed" ] || min_speed=0
  set_raw CFST_MIN_SPEED "$min_speed"
  echo "测速参数已保存。"
}

toggle_push_mode() {
  current="$(get_value PUSH_MODE)"
  if [ "$current" = "domain" ]; then
    set_value PUSH_MODE "ip"
    echo "已切换为 IP 直接推送模式（不更新 Cloudflare DNS）"
  else
    set_value PUSH_MODE "domain"
    echo "已切换为域名解析推送模式"
  fi
}

toggle_cdn_source() {
  current="$(get_value CDN_IP_MODE)"
  if [ "$current" = "reverse" ]; then
    set_value CDN_IP_MODE "official"
    echo "已切换为 Cloudflare CDN 官方 IP 模式"
  else
    set_value CDN_IP_MODE "reverse"
    echo "已切换为 CDN 反代 IP 模式"
  fi
}

toggle_domain_mode() {
  current="$(get_value DOMAIN_UPDATE_MODE)"
  if [ "$current" = "one_to_one" ]; then
    set_value DOMAIN_UPDATE_MODE "multi"
    echo "已切换为多个优选 IP 解析到一个域名方案"
  else
    set_value DOMAIN_UPDATE_MODE "one_to_one"
    echo "已切换为每个优选 IP 解析到每个域名方案"
  fi
}

configure_domains() {
  echo
  if [ "$(get_value DOMAIN_UPDATE_MODE)" = "one_to_one" ]; then
    printf "请输入多个完整解析域名，空格分隔，例如 a.example.com b.example.com: "
    read -r names
    [ -n "$names" ] && set_value CF_RECORD_NAMES "$names"
  else
    printf "请输入完整解析域名，例如 best.example.com: "
    read -r record
    [ -n "$record" ] && set_value CF_RECORD_NAME "$record"
  fi
  echo "域名配置已保存。"
}

configure_proxy_plugin() {
  echo
  echo "0. 不使用任何插件"
  echo "1. Passwall"
  echo "2. Passwall2"
  echo "3. SSR-Plus"
  echo "4. Clash"
  echo "5. OpenClash"
  echo "6. Bypass"
  echo "7. V2raya"
  echo "8. Hello-World"
  echo "9. Homeproxy"
  echo "10. MihomoTProxy"
  echo "11. ShellCrash"
  printf "请输入代理插件编号（默认 0）: "
  read -r plugin
  [ -n "$plugin" ] || plugin=0
  set_raw PROXY_PLUGIN "$plugin"
  echo "代理插件配置已保存：$(plugin_name "$plugin")"
}

configure_wait() {
  configure_threads
  printf "请输入重启代理插件后的等待时间秒数（默认 30）: "
  read -r wait_time
  [ -n "$wait_time" ] || wait_time=30
  set_raw PROXY_RESTART_WAIT "$wait_time"
  echo "等待时间已保存。"
}

configure_telegram() {
  echo
  printf "是否启用 Telegram 通知？选择 1 启用，回车关闭: "
  read -r choice
  if [ "$choice" = "1" ]; then
    printf "请输入 Telegram Bot Token: "
    read -r bot_token
    printf "请输入 Telegram 用户 ID: "
    read -r user_id
    set_value TELEGRAM_BOT_TOKEN "$bot_token"
    set_value TELEGRAM_USER_ID "$user_id"
  else
    set_value TELEGRAM_BOT_TOKEN ""
    set_value TELEGRAM_USER_ID ""
  fi
  echo "Telegram 配置已保存。"
}

configure_telegram_api() {
  printf "请输入 Telegram API 域名（默认 api.telegram.org）: "
  read -r api
  [ -n "$api" ] || api="api.telegram.org"
  set_value TELEGRAM_API "$api"
  echo "Telegram API 已保存。"
}

configure_pushplus() {
  echo
  printf "是否启用 PushPlus 微信通知？选择 1 启用，回车关闭: "
  read -r choice
  if [ "$choice" = "1" ]; then
    printf "请输入 PushPlus Token: "
    read -r token
    set_value PUSHPLUS_TOKEN "$token"
  else
    set_value PUSHPLUS_TOKEN ""
  fi
  echo "PushPlus 配置已保存。"
}

toggle_dry_run() {
  current="$(get_value DRY_RUN)"
  if [ "$current" = "1" ]; then
    set_raw DRY_RUN 0
    echo "已切换为 DRY_RUN=0，下次会真实更新或删除 Cloudflare DNS。"
  else
    set_raw DRY_RUN 1
    echo "已切换为 DRY_RUN=1，下次只测试，不改 DNS。"
  fi
}

change_menu() {
  while true; do
    clear 2>/dev/null || true
    echo "更改各项参数配置"
    echo "================"
    echo "1. 切换推送模式（域名解析推送 / IP 直接推送）"
    echo "2. 切换 CDN IP 来源（官方 IP / 反代 IP）"
    echo "3. 切换域名解析方案（多 IP 到一域名 / 每 IP 到每域名）"
    echo "4. 切换优选 IPv4 或 IPv6"
    echo "5. 更换端口"
    echo "6. 开启、关闭测速，更换测速网站"
    echo "7. 更换 OpenWrt 代理插件"
    echo "8. 更改测速线程、显示数量、超时、延迟/速度阈值、代理重启等待时间"
    echo "9. 更换 Cloudflare 解析域名"
    echo "10. 更换 Cloudflare API Token / Zone ID"
    echo "11. 关闭、开启 Telegram 通知，更换 Token、用户 ID"
    echo "12. 切换 Telegram API 接口域名"
    echo "13. 关闭、开启 PushPlus 微信通知，更换 Token"
    echo "14. 切换 DRY_RUN 安全测试模式"
    echo "15. 查看当前配置"
    echo "0. 返回主菜单"
    echo
    printf "请输入: "
    read -r choice
    case "$choice" in
      1) toggle_push_mode; pause ;;
      2) toggle_cdn_source; pause ;;
      3) toggle_domain_mode; pause ;;
      4) configure_ip_version; pause ;;
      5) configure_port; pause ;;
      6) configure_speed_url; pause ;;
      7) configure_proxy_plugin; pause ;;
      8) configure_wait; pause ;;
      9) configure_domains; pause ;;
      10) configure_cloudflare; pause ;;
      11) configure_telegram; pause ;;
      12) configure_telegram_api; pause ;;
      13) configure_pushplus; pause ;;
      14) toggle_dry_run; pause ;;
      15) print_status; pause ;;
      0) return ;;
      *) echo "输入有误"; pause ;;
    esac
  done
}

install_flow() {
  ensure_config
  echo
  echo "安装/重置脚本配置向导"
  echo "===================="
  echo "1. 域名解析推送模式（需要域名，推荐）"
  echo "2. IP 直接推送模式（无需域名）"
  printf "请选择: "
  read -r push_choice
  [ "$push_choice" = "2" ] && set_value PUSH_MODE "ip" || set_value PUSH_MODE "domain"

  if [ "$(get_value PUSH_MODE)" = "domain" ]; then
    echo "1. 多个优选 IP 解析到一个域名"
    echo "2. 每个优选 IP 解析到每个域名"
    printf "请选择: "
    read -r domain_choice
    [ "$domain_choice" = "2" ] && set_value DOMAIN_UPDATE_MODE "one_to_one" || set_value DOMAIN_UPDATE_MODE "multi"
    configure_domains
    configure_cloudflare
  fi

  echo "1. Cloudflare CDN 官方 IP（推荐）"
  echo "2. CDN 反代 IP"
  printf "请选择（回车默认官方 IP）: "
  read -r source_choice
  [ "$source_choice" = "2" ] && set_value CDN_IP_MODE "reverse" || set_value CDN_IP_MODE "official"

  configure_ip_version
  configure_port
  configure_speed_url
  configure_threads
  configure_proxy_plugin
  printf "请输入重启代理插件后的等待时间秒数（默认 30）: "
  read -r wait_time
  [ -n "$wait_time" ] || wait_time=30
  set_raw PROXY_RESTART_WAIT "$wait_time"
  configure_telegram
  configure_pushplus
  set_raw DRY_RUN 1
  echo "配置完成。首次已保持 DRY_RUN=1，请先运行一次测试。"
}

run_now() {
  ensure_config
  chmod +x "$RUNNER"
  "$RUNNER"
}

delete_dns_records() {
  ensure_config
  echo "删除 CF 域名指定名称解析记录"
  echo "当前 DRY_RUN=$(get_value DRY_RUN)。DRY_RUN=1 时只预览不删除。"
  configure_cloudflare
  printf "请输入要删除的完整解析域名，例如 best.example.com: "
  read -r name
  [ -n "$name" ] || name="$(get_value CF_RECORD_NAME)"
  DELETE_RECORD_NAME="$name" "$RUNNER" delete-records
}

show_log() {
  if [ -f "$LOG_FILE" ]; then
    tail -n 120 "$LOG_FILE"
  else
    echo "暂无日志：$LOG_FILE"
  fi
}

remove_project() {
  echo "即将卸载：$APP_DIR"
  printf "确认卸载请输入 YES: "
  read -r confirm
  if [ "$confirm" = "YES" ]; then
    rm -rf "$APP_DIR"
    echo "卸载完成"
    exit 0
  fi
  echo "已取消卸载"
}

main_menu() {
  ensure_config
  while true; do
    clear 2>/dev/null || true
    echo "--------------------------------------------------------------"
    echo "OpenWrt软路由-优选IP解析到CF域名脚本（安全修正版）"
    echo "--------------------------------------------------------------"
    print_status
    echo "--------------------------------------------------------------"
    echo "1.安装/重置脚本"
    echo "2.更改各项参数配置"
    echo "3.运行一次已配置完成的脚本"
    echo "4.删除CF域名指定名称解析记录"
    echo "5.卸载"
    echo "6.查看运行日志"
    echo "0.退出"
    echo
    printf "请选择: "
    read -r choice
    case "$choice" in
      1) install_flow; pause ;;
      2) change_menu ;;
      3) run_now; pause ;;
      4) delete_dns_records; pause ;;
      5) remove_project; pause ;;
      6) show_log; pause ;;
      0) exit 0 ;;
      *) echo "输入有误"; pause ;;
    esac
  done
}

main_menu
