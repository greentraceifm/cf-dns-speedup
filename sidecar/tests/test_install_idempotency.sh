#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

. "$ROOT/install-sidecar.sh"
[ "$SOURCE_DIR" = "$ROOT" ]

printf 'same-file\n' >"$TMP_DIR/source"
chmod 0600 "$TMP_DIR/source"
install_managed_file 0644 "$TMP_DIR/source" "$TMP_DIR/source"

install_managed_file 0600 "$TMP_DIR/source" "$TMP_DIR/target"
cmp "$TMP_DIR/source" "$TMP_DIR/target"

case "$(uname -s)" in
  MINGW*|MSYS*) ;;
  *)
    [ "$(stat -c '%a' "$TMP_DIR/source")" = "644" ]
    [ "$(stat -c '%a' "$TMP_DIR/target")" = "600" ]
    ;;
esac

echo "install idempotency test passed"
