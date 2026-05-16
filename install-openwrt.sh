#!/usr/bin/env sh
set -eu

APP_DIR="${APP_DIR:-/root/cf-dns-speedup}"
REPO_RAW_BASE="${REPO_RAW_BASE:-https://raw.githubusercontent.com/greentraceifm/cf-dns-speedup/main}"

mkdir -p "$APP_DIR"

if [ -n "$REPO_RAW_BASE" ]; then
  curl -fL --connect-timeout 10 --max-time 60 -o "$APP_DIR/cf-dns-speedup.sh" "$REPO_RAW_BASE/cf-dns-speedup.sh"
  curl -fL --connect-timeout 10 --max-time 60 -o "$APP_DIR/config.example.env" "$REPO_RAW_BASE/config.example.env"
  curl -fL --connect-timeout 10 --max-time 60 -o "$APP_DIR/menu.sh" "$REPO_RAW_BASE/menu.sh"
else
  echo "REPO_RAW_BASE is empty; copy cf-dns-speedup.sh and config.example.env manually." >&2
fi

chmod +x "$APP_DIR/cf-dns-speedup.sh"
chmod +x "$APP_DIR/menu.sh"

if [ ! -f "$APP_DIR/config.env" ]; then
  cp "$APP_DIR/config.example.env" "$APP_DIR/config.env"
  chmod 600 "$APP_DIR/config.env"
fi

echo "Installed to $APP_DIR"
echo "Opening setup menu..."
if [ -r /dev/tty ]; then
  "$APP_DIR/menu.sh" </dev/tty
else
  echo "No interactive terminal detected. Run this later:"
  echo "  $APP_DIR/menu.sh"
fi
