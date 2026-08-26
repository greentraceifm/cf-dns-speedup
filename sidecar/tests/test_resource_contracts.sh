#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1 || ! "$PYTHON_BIN" -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
  PYTHON_BIN=python
fi
TMP_DIR="$(mktemp -d)"
export SIDECAR_CONFIG_FILE="$TMP_DIR/missing.env"
export SIDECAR_RUN_DIR="$TMP_DIR/run"
export SIDECAR_DATA_DIR="$TMP_DIR/data"
export SIDECAR_ASSET_DIR="$TMP_DIR/assets"
export SIDECAR_RUNTIME_IMAGE_ID_FILE="$TMP_DIR/data/runtime-image.id"
mkdir -p "$SIDECAR_RUN_DIR" "$SIDECAR_DATA_DIR" "$SIDECAR_ASSET_DIR"
trap 'rm -rf "$TMP_DIR"' EXIT

# shellcheck source=/dev/null
. "$ROOT/cfip-sidecar.sh"

[ "$SIDECAR_REQUIRED_CONTAINERS" = "sub2api sub2api-postgres sub2api-redis" ] \
  || { echo "unexpected default required-container contract" >&2; exit 1; }

NETWORK_MODE=l2
network_json() {
  printf '[{"Driver":"ipvlan","Options":{"parent":"ens160","ipvlan_mode":"%s"},"IPAM":{"Config":[{"Subnet":"192.168.1.0/24","Gateway":"192.168.1.254"}]}}]\n' "$NETWORK_MODE"
}
network_check || { echo "valid ipvlan L2 network was rejected" >&2; exit 1; }
NETWORK_MODE=l3
if network_check; then
  echo "ipvlan mode other than L2 was accepted" >&2
  exit 1
fi

MOCK_IMAGE_ID="sha256:$(printf 'a%.0s' {1..64})"
mock_docker() {
  if [ "${1:-}" = "image" ] && [ "${2:-}" = "inspect" ]; then
    printf '%s\n' "$MOCK_IMAGE_ID"
    return 0
  fi
  return 1
}
DOCKER_BIN=mock_docker
printf '#!/bin/sh\nexit 0\n' >"$SIDECAR_ASSET_DIR/cfst"
chmod 0755 "$SIDECAR_ASSET_DIR/cfst"
printf '104.16.0.0/13\n' >"$SIDECAR_ASSET_DIR/ip.txt"
printf '%s\n' "$MOCK_IMAGE_ID" >"$SIDECAR_RUNTIME_IMAGE_ID_FILE"
image_check || { echo "recorded runtime image identity was rejected" >&2; exit 1; }
printf 'sha256:%s\n' "$(printf 'b%.0s' {1..64})" >"$SIDECAR_RUNTIME_IMAGE_ID_FILE"
if (image_check); then
  echo "runtime image identity drift was accepted" >&2
  exit 1
fi
printf 'not-an-image-id\n' >"$SIDECAR_RUNTIME_IMAGE_ID_FILE"
if (image_check); then
  echo "invalid runtime image identity was accepted" >&2
  exit 1
fi

maintenance_lock="$TMP_DIR/maintenance.lock"
printf '\n' >"$maintenance_lock"
SIDECAR_HOST_MAINTENANCE_LOCKS="$maintenance_lock"
if command -v flock >/dev/null 2>&1; then
  exec 8>"$maintenance_lock"
  flock -n 8
  if (assert_host_maintenance_idle); then
    echo "held host maintenance lock was accepted" >&2
    exit 1
  fi
  flock -u 8
  exec 8>&-
  assert_host_maintenance_idle || { echo "free host maintenance lock was rejected" >&2; exit 1; }
  SIDECAR_HOST_MAINTENANCE_LOCKS="$TMP_DIR/absent.lock"
  assert_host_maintenance_idle || { echo "absent host maintenance lock was rejected" >&2; exit 1; }
else
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      echo "host maintenance lock runtime test skipped: flock is unavailable in Windows Git Bash"
      ;;
    *)
      echo "flock is required for native lock validation" >&2
      exit 1
      ;;
  esac
fi

echo "resource contract test passed"
