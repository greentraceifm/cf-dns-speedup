#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SIDECAR_INSTALL_DIR:-/opt/cfip-sidecar}"
CONFIG_DIR="${SIDECAR_CONFIG_DIR:-/etc/cfip-sidecar}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
TMPFILES_DIR="${TMPFILES_DIR:-/etc/tmpfiles.d}"
require_root() { [ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }; }

install_managed_file() {
  local mode="$1" source="$2" target="$3"
  if [ -e "$target" ] && [ "$source" -ef "$target" ]; then
    chmod "$mode" "$target"
  else
    install -m "$mode" "$source" "$target"
  fi
}

install_files() {
  require_root
  install -d -m 0755 "$INSTALL_DIR" "$INSTALL_DIR/assets" "$CONFIG_DIR"
  install_managed_file 0755 "$SOURCE_DIR/cfip-sidecar.sh" "$INSTALL_DIR/cfip-sidecar.sh"
  install_managed_file 0755 "$SOURCE_DIR/build-runtime-image.sh" "$INSTALL_DIR/build-runtime-image.sh"
  install_managed_file 0755 "$SOURCE_DIR/install-sidecar.sh" "$INSTALL_DIR/install-sidecar.sh"
  install_managed_file 0755 "$SOURCE_DIR/render-xray-config.py" "$INSTALL_DIR/render-xray-config.py"
  install_managed_file 0755 "$SOURCE_DIR/router-bypass.sh" "$INSTALL_DIR/router-bypass.sh"
  install_managed_file 0644 "$SOURCE_DIR/cfip-sidecar.env.example" "$INSTALL_DIR/cfip-sidecar.env.example"
  install_managed_file 0644 "$SOURCE_DIR/cfip-sidecar.service" "$INSTALL_DIR/cfip-sidecar.service"
  install_managed_file 0644 "$SOURCE_DIR/cfip-sidecar.timer" "$INSTALL_DIR/cfip-sidecar.timer"
  install_managed_file 0644 "$SOURCE_DIR/cfip-sidecar.tmpfiles" "$INSTALL_DIR/cfip-sidecar.tmpfiles"
  [ -e "$CONFIG_DIR/sidecar.env" ] || install -m 0600 "$INSTALL_DIR/cfip-sidecar.env.example" "$CONFIG_DIR/sidecar.env"
  install_managed_file 0644 "$INSTALL_DIR/cfip-sidecar.service" "$SYSTEMD_DIR/cfip-sidecar.service"
  install_managed_file 0644 "$INSTALL_DIR/cfip-sidecar.timer" "$SYSTEMD_DIR/cfip-sidecar.timer"
  install_managed_file 0644 "$INSTALL_DIR/cfip-sidecar.tmpfiles" "$TMPFILES_DIR/cfip-sidecar.conf"
  systemd-tmpfiles --create "$TMPFILES_DIR/cfip-sidecar.conf"
  systemctl daemon-reload
  echo "installed; timer enablement state was not changed"
}

enable_timer() { require_root; systemctl enable cfip-sidecar.timer; systemctl start cfip-sidecar.timer; systemctl is-enabled cfip-sidecar.timer; systemctl is-active cfip-sidecar.timer; }
disable_timer() { require_root; systemctl disable --now cfip-sidecar.timer 2>/dev/null || true; }

main() {
  case "${1:-}" in
    install) install_files ;;
    enable-timer) enable_timer ;;
    disable-timer) disable_timer ;;
    *) echo "Usage: $0 {install|enable-timer|disable-timer}" >&2; exit 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
