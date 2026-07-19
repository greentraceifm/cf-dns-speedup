#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/cfip-sidecar.sh"
UNIT="$ROOT/cfip-sidecar-diagnose@.service"

grep -q '^    diagnose) diagnose "${2:-}" ;;$' "$SCRIPT"
grep -q 'candidate_baseline candidate primary' "$SCRIPT"
grep -q 'candidate_relaxed candidate primary' "$SCRIPT"
grep -q 'profile_relaxed profile primary' "$SCRIPT"
grep -q 'candidate_alt candidate alternate' "$SCRIPT"
grep -q 'no scan, DNS, PassWall, or pool update was attempted' "$SCRIPT"
grep -q '^ExecStart=/opt/cfip-sidecar/cfip-sidecar.sh diagnose %I$' "$UNIT"
grep -q '^ExecStart=/opt/cfip-sidecar/cfip-sidecar.sh observe$' "$ROOT/cfip-sidecar.service"
if grep -q '^\[Install\]$' "$UNIT"; then
  echo "diagnostic unit must remain manual-only" >&2
  exit 1
fi
if grep -q 'diagnose' "$ROOT/cfip-sidecar.timer"; then
  echo "nightly timer must not invoke diagnostics" >&2
  exit 1
fi
if grep -q '/var/lib/cfip-sidecar-export' "$UNIT"; then
  echo "diagnostic unit must not gain write access to the candidate export directory" >&2
  exit 1
fi
header="$(grep "^  printf 'observed_at\\\\treference_candidate_ip" "$SCRIPT")"
case "$header" in
  *profile_sha256*) echo "diagnostic report must not contain a profile hash" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
touch "$tmp/export-blocker"
(
  export SIDECAR_RUN_DIR="$tmp/run"
  export SIDECAR_DATA_DIR="$tmp/data"
  export SIDECAR_EXPORT_DIR="$tmp/export-blocker/child"
  # shellcheck source=../cfip-sidecar.sh
  source "$SCRIPT"

  prepare_dirs
  [ -d "$SIDECAR_RUN_DIR" ]
  [ -d "$SIDECAR_DATA_DIR/diagnostics" ]

  SIDECAR_EXPORT_DIR="$tmp/export"
  prepare_export_dir
  [ -d "$SIDECAR_EXPORT_DIR" ]
  [ "$(stat -c '%a' "$SIDECAR_EXPORT_DIR")" = 755 ]
)

echo "diagnostic contract test passed"
