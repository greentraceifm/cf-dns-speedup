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
    *) echo "********" ;;
  esac
}

print_status() {
  ensure_config
  echo
  echo "当前配置："
  echo "1、当前为域名解析推送模式（需要域名，推荐）"
  echo "2、当前为 Cloudflare CDN 官方 IP 模式"
  echo "3、当前为单域名记录更新方案"
  echo "4、当前为优选 $(get_value IP_VERSION)"
  echo "5、使用的端口：$(get_value CFST_PORT)"
  if [ -n "$(get_value CFST_URL)" ]; then
    echo "6、测速已开启，测速地址：$(get_value CFST_URL)"
  else
    echo "6、当前为延迟优选模式，未开启下载测速"
  fi
  echo "7、代理插件控制：关闭（安全版不自动停止或重启代理插件）"
  echo "8、cfst 总超时：$(get_value CFST_TOTAL_TIMEOUT) 秒"
  echo "9、更新域名：$(get_value CF_RECORD_NAME)"
  echo "10、Cloudflare Zone ID：$(get_value CF_ZONE_ID)"
  echo "11、Cloudflare API Token：$(mask_token "$(get_value CF_API_TOKEN)")"
  echo "12、DRY_RUN：$(get_value DRY_RUN)"
  echo "13、测速线程/数量：$(get_value CFST_THREADS)/$(get_value CFST_COUNT)"
}

configure_cloudflare() {
  ensure_config
  echo
  echo "配置 Cloudflare 信息"
  printf "请输入 Cloudflare API Token（建议 Zone:Read + DNS:Edit 最小权限）: "
  read -r token
  [ -n "$token" ] && set_value CF_API_TOKEN "$token"
  printf "请输入 Cloudflare 区域 ID Zone ID: "
  read -r zone
  [ -n "$zone" ] && set_value CF_ZONE_ID "$zone"
  printf "请输入完整解析域名，例如 best.example.com: "
  read -r record
  [ -n "$record" ] && set_value CF_RECORD_NAME "$record"
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
  echo "2. 关闭下载测速，只做延迟优选（推荐更稳）"
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
  printf "请输入显示/更新的 IP 数量（默认 5）: "
  read -r count
  [ -n "$count" ] || count=5
  set_raw CFST_COUNT "$count"
  printf "请输入 cfst 总超时秒数（默认 900，防止卡死）: "
  read -r total_timeout
  [ -n "$total_timeout" ] || total_timeout=900
  set_raw CFST_TOTAL_TIMEOUT "$total_timeout"
  echo "测速参数已保存。"
}

toggle_dry_run() {
  ensure_config
  current="$(get_value DRY_RUN)"
  if [ "$current" = "1" ]; then
    set_raw DRY_RUN 0
    echo "已切换为 DRY_RUN=0，下次会真实更新 Cloudflare DNS。"
  else
    set_raw DRY_RUN 1
    echo "已切换为 DRY_RUN=1，下次只测试，不改 DNS。"
  fi
}

change_menu() {
  while true; do
    clear 2>/dev/null || true
    echo "变更参数配置"
    echo "============"
    echo "1. 切换推送模式（安全版固定为域名解析推送）"
    echo "2. 切换 CDN IP 来源（安全版固定为官方 IP 列表）"
    echo "3. 切换域名解析方案（安全版固定为单记录更新）"
    echo "4. 切换优选 IPv4 / IPv6"
    echo "5. 更换端口"
    echo "6. 开启、关闭测速，更换测速网站"
    echo "7. 更换代理插件（安全版不自动控制代理插件）"
    echo "8. 更改 cfst 总超时时间、线程、结果数量"
    echo "9. 更换 Cloudflare 解析域名"
    echo "10. 更换 Cloudflare API Token / Zone ID"
    echo "11. 通知配置（暂未实现，避免保存第三方 token）"
    echo "12. 切换 DRY_RUN 安全测试模式"
    echo "13. 查看当前配置"
    echo "14. 返回主菜单"
    echo
    printf "请输入: "
    read -r choice
    case "$choice" in
      1|2|3|7|11) echo "安全版保留该菜单项，但不执行此类高风险自动变更。"; pause ;;
      4) configure_ip_version; pause ;;
      5) configure_port; pause ;;
      6) configure_speed_url; pause ;;
      8) configure_threads; pause ;;
      9) printf "请输入完整解析域名，例如 best.example.com: "; read -r record; [ -n "$record" ] && set_value CF_RECORD_NAME "$record"; pause ;;
      10) configure_cloudflare; pause ;;
      12) toggle_dry_run; pause ;;
      13) print_status; pause ;;
      14) return ;;
      *) echo "输入有误"; pause ;;
    esac
  done
}

install_flow() {
  ensure_config
  echo
  echo "首次配置向导"
  echo "=========="
  configure_cloudflare
  configure_ip_version
  configure_port
  configure_speed_url
  configure_threads
  echo
  echo "首次建议保持 DRY_RUN=1，先测试不修改 DNS。"
  set_raw DRY_RUN 1
  echo "配置完成。"
}

run_now() {
  ensure_config
  chmod +x "$RUNNER"
  "$RUNNER"
}

show_log() {
  if [ -f "$LOG_FILE" ]; then
    tail -n 100 "$LOG_FILE"
  else
    echo "暂无日志：$LOG_FILE"
  fi
}

remove_project() {
  echo "为了防止误删，安全版不自动删除目录。"
  echo "如确认卸载，请手动删除目录：$APP_DIR"
}

main_menu() {
  ensure_config
  while true; do
    clear 2>/dev/null || true
    echo "Cloudflare 优选 IP 自动更新脚本（安全修正版）"
    echo "=========================================="
    echo "1. 安装/首次配置"
    echo "2. 变更参数配置"
    echo "3. 立即执行优选并更新 DNS"
    echo "4. 域名清理（安全版暂不自动批量删除 DNS）"
    echo "5. 卸载脚本"
    echo "6. 查看当前配置"
    echo "7. 查看运行日志"
    echo "0. 退出"
    echo
    printf "请选择: "
    read -r choice
    case "$choice" in
      1) install_flow; pause ;;
      2) change_menu ;;
      3) run_now; pause ;;
      4) echo "安全版不做批量删除 DNS。请在 Cloudflare 后台确认后手动清理。"; pause ;;
      5) remove_project; pause ;;
      6) print_status; pause ;;
      7) show_log; pause ;;
      0) exit 0 ;;
      *) echo "输入有误"; pause ;;
    esac
  done
}

main_menu
