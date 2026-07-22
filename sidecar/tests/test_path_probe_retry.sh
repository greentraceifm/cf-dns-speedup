#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
export SIDECAR_CONFIG_FILE="$TMP_DIR/missing.env"
export SIDECAR_RUN_DIR="$TMP_DIR/run"
export SIDECAR_DATA_DIR="$TMP_DIR/data"
export SIDECAR_PATH_CHECK_ATTEMPTS=3
export SIDECAR_PATH_CHECK_RETRY_DELAY=0

# shellcheck source=/dev/null
. "$ROOT/cfip-sidecar.sh"
trap 'rm -rf "$TMP_DIR"' EXIT

attempt_file="$TMP_DIR/flaky-attempts"
flaky_probe() {
  local count=0
  [ ! -f "$attempt_file" ] || count="$(cat "$attempt_file")"
  count=$((count + 1))
  printf '%s\n' "$count" >"$attempt_file"
  [ "$count" -ge 3 ] || return 1
  printf 'ip=203.0.113.10\n'
}

result="$(capture_public_ip_with_retries "flaky test probe" flaky_probe)"
[ "$result" = "203.0.113.10" ] || { echo "retry result mismatch: $result" >&2; exit 1; }
[ "$(cat "$attempt_file")" = "3" ] || { echo "flaky probe did not retry three times" >&2; exit 1; }

[ -z "$(extract_public_ip '<html>temporary upstream error</html>')" ] \
  || { echo "non-IP path response was accepted" >&2; exit 1; }

attempt_file="$TMP_DIR/invalid-response-attempts"
invalid_response_probe() {
  local count=0
  [ ! -f "$attempt_file" ] || count="$(cat "$attempt_file")"
  count=$((count + 1))
  printf '%s\n' "$count" >"$attempt_file"
  printf '<html>temporary upstream error</html>\n'
}
if capture_public_ip_with_retries "invalid response probe" invalid_response_probe; then
  echo "invalid path responses unexpectedly succeeded" >&2
  exit 1
fi
[ "$(cat "$attempt_file")" = "3" ] || { echo "invalid response probe did not retry" >&2; exit 1; }

attempt_file="$TMP_DIR/failing-attempts"
always_fail_probe() {
  local count=0
  [ ! -f "$attempt_file" ] || count="$(cat "$attempt_file")"
  count=$((count + 1))
  printf '%s\n' "$count" >"$attempt_file"
  return 1
}

if capture_public_ip_with_retries "failing test probe" always_fail_probe; then
  echo "exhausted retries unexpectedly succeeded" >&2
  exit 1
fi
[ "$(cat "$attempt_file")" = "3" ] || { echo "failing probe did not stop after three attempts" >&2; exit 1; }

SIDECAR_PATH_CHECK_ATTEMPTS=0
if (validate_path_probe_settings); then
  echo "zero retry attempts should be rejected" >&2
  exit 1
fi
SIDECAR_PATH_CHECK_ATTEMPTS=3
SIDECAR_PATH_CHECK_RETRY_DELAY=invalid
if (validate_path_probe_settings); then
  echo "non-numeric retry delay should be rejected" >&2
  exit 1
fi

SIDECAR_PATH_CHECK_URL=http://example.test/trace
if (validate_path_probe_settings); then
  echo "non-HTTPS path probe URL should be rejected" >&2
  exit 1
fi
SIDECAR_PATH_CHECK_URL=https://example.test/trace
SIDECAR_PATH_CHECK_ATTEMPTS=3
SIDECAR_PATH_CHECK_RETRY_DELAY=0
host_public_ip_probe_once() {
  printf 'ip=203.0.113.10\n'
}
sidecar_public_ip_probe_once() {
  printf 'ip=203.0.113.10\n'
}
if (trap - EXIT; network_probe >/dev/null 2>&1); then
  echo "matching host and Sidecar exits must remain fail-closed" >&2
  exit 1
fi

echo "path probe retry test passed"
