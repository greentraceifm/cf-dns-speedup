#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"

export SIDECAR_CONFIG_FILE="$TMP_DIR/missing.env"
export SIDECAR_RUN_DIR="$TMP_DIR/run"
export SIDECAR_DATA_DIR="$TMP_DIR/data"
export SIDECAR_EXPORT_DIR="$TMP_DIR/export"

# shellcheck source=/dev/null
. "$ROOT/cfip-sidecar.sh"
trap 'rm -rf "$TMP_DIR"' EXIT

prepare_dirs
tracked="$SIDECAR_RUN_DIR/xray-tracked.json"
unknown="$SIDECAR_RUN_DIR/xray-unknown.json"
printf '%s\n' tracked >"$tracked"
printf '%s\n' unknown >"$unknown"
ACTIVE_CONFIGS=("$tracked")
cleanup
[ ! -e "$tracked" ] || { echo "tracked Xray config was not removed" >&2; exit 1; }
[ -e "$unknown" ] || { echo "unknown Xray config was removed" >&2; exit 1; }

if (assert_no_xray_residue); then
  echo "unknown Xray residue was not rejected" >&2
  exit 1
fi
rm -f -- "$unknown"
assert_no_xray_residue

directory_residue="$SIDECAR_RUN_DIR/xray-directory.json"
mkdir "$directory_residue"
if (assert_no_xray_residue); then
  echo "non-file Xray residue was not rejected" >&2
  exit 1
fi
rmdir "$directory_residue"
assert_no_xray_residue

render_stub() {
  local output=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--output" ]; then
      output="$2"
      shift 2
    else
      shift
    fi
  done
  printf '%s\n' partial >"$output"
  return 1
}

PYTHON_BIN=render_stub
config="$SIDECAR_RUN_DIR/xray-render-failure.json"
marker="$TMP_DIR/render-failure-cleaned"
set +e
(
  set -e
  trap 'cleanup; [ ! -e "$config" ] && : >"$marker"' EXIT
  start_xray 203.0.113.10 "$config" cfip-test-render-failure
)
render_status=$?
set -e
if [ "$render_status" -eq 0 ]; then
  echo "render failure unexpectedly succeeded" >&2
  exit 1
fi
[ -e "$marker" ] || { echo "render failure cleanup trap did not run" >&2; exit 1; }
[ ! -e "$config" ] || { echo "partially rendered config survived cleanup" >&2; exit 1; }

echo "Xray residue guard test passed"
