#!/usr/bin/env sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! "$PYTHON_BIN" --version >/dev/null 2>&1; then
  PYTHON_BIN=python
fi
bash -n "$ROOT/sidecar/cfip-sidecar.sh"
bash -n "$ROOT/sidecar/build-runtime-image.sh"
bash -n "$ROOT/sidecar/install-sidecar.sh"
sh -n "$ROOT/sidecar/router-bypass.sh"
"$PYTHON_BIN" "$ROOT/sidecar/tests/test_render_xray_config.py" 2>&1
bash "$ROOT/sidecar/tests/test_candidate_export.sh"
bash "$ROOT/sidecar/tests/test_install_idempotency.sh"
bash "$ROOT/sidecar/tests/test_diagnostic_contract.sh"
bash "$ROOT/sidecar/tests/test_path_probe_retry.sh"
grep -q 'SIDECAR_REQUIRE_DIFFERENT_PUBLIC_IP=1' "$ROOT/sidecar/cfip-sidecar.env.example"
grep -q 'SIDECAR_PATH_CHECK_ATTEMPTS=3' "$ROOT/sidecar/cfip-sidecar.env.example"
grep -q 'SIDECAR_PATH_CHECK_RETRY_DELAY=3' "$ROOT/sidecar/cfip-sidecar.env.example"
grep -q 'CFIP Sidecar direct bypass' "$ROOT/sidecar/router-bypass.sh"
grep -q 'counter return comment' "$ROOT/sidecar/router-bypass.sh"
if grep -q -- ' -k ' "$ROOT/sidecar/cfip-sidecar.sh"; then
  echo "insecure curl TLS bypass is forbidden" >&2
  exit 1
fi
grep -q '^Persistent=false$' "$ROOT/sidecar/cfip-sidecar.timer"
grep -q '^TimeoutStartSec=75min$' "$ROOT/sidecar/cfip-sidecar.service"
grep -q '^TimeoutStartSec=20min$' "$ROOT/sidecar/cfip-sidecar-diagnose@.service"
grep -q '"$SOURCE_DIR/cfip-sidecar.service" "$INSTALL_DIR/cfip-sidecar.service"' "$ROOT/sidecar/install-sidecar.sh"
grep -q '"$SOURCE_DIR/cfip-sidecar-diagnose@.service" "$INSTALL_DIR/cfip-sidecar-diagnose@.service"' "$ROOT/sidecar/install-sidecar.sh"
grep -q '^d /run/cfip-sidecar 0700 root root' "$ROOT/sidecar/cfip-sidecar.tmpfiles"
grep -q '^d /var/lib/cfip-sidecar-export 0755 root root' "$ROOT/sidecar/cfip-sidecar.tmpfiles"
echo "all sidecar tests passed"
