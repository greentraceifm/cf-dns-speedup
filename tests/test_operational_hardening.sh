#!/usr/bin/env sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MAIN="$ROOT_DIR/cf-dns-speedup.sh"
INSTALLER="$ROOT_DIR/install-openwrt.sh"
MENU="$ROOT_DIR/menu.sh"
OBSERVER="$ROOT_DIR/passwall-node-observe.sh"

grep -q '^umask 077$' "$MAIN"
grep -Fq 'chmod 600 "$config_path"' "$MAIN"
grep -Fq 'chmod 600 "$CONFIG_FILE"' "$MAIN"
grep -Fq 'CFST_PASSWALL_HEALTH_PORTS=' "$MAIN"
grep -Fq 'passwall_xray_processes=' "$MAIN"
grep -Fq 'passwall_runtime_healthy=' "$MAIN"
grep -Fq 'CFST_PASSWALL_HEALTH_PORTS="1070 1041 11400 15353"' "$ROOT_DIR/config.example.env"
grep -Fq 'observe-current >/tmp/cf-dns-speedup.observe.log' "$MAIN"
grep -A3 '^observe_current_command()' "$MAIN" | grep -q 'rotate_logs'
grep -Fq 'chmod 600 "$APP_DIR/config.env"' "$INSTALLER"
grep -Fq 'chmod 600 "$CONFIG_FILE"' "$MENU"
grep -q '^umask 077$' "$OBSERVER"
grep -Fq 'PASSWALL_NODE_OBSERVE_LOG_MAX_KB' "$OBSERVER"
grep -Fq 'mv -f "$LOG_FILE" "$LOG_FILE.1"' "$OBSERVER"

echo "operational hardening test passed"
