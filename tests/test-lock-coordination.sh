#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

if ! command -v flock >/dev/null 2>&1; then
  echo "lock coordination test skipped: real flock is unavailable"
  exit 0
fi

MAIN_LINE="$(grep -n '^main ' "$ROOT/cf-dns-speedup.sh" | tail -n 1 | cut -d: -f1)"
[ -n "$MAIN_LINE" ]
head -n "$((MAIN_LINE - 1))" "$ROOT/cf-dns-speedup.sh" >"$TEST_TMP/lib.sh"

load_main_lock() {
  APP_DIR="$TEST_TMP/app"
  LOCK_DIR="$TEST_TMP/main.lock"
  CFIP_AUTO_SYNC_LOCK_FILE="$TEST_TMP/sync.lock"
  CFIP_CANDIDATE_GATE_LOCK="$TEST_TMP/gate.lock"
  CFST_PASSWALL_NODE_OBSERVE_LOCK="$TEST_TMP/observe.lock"
  LOCK_ACQUIRED=0
  # shellcheck disable=SC1090
  . "$TEST_TMP/lib.sh"
}

start_holder() {
  local lock="$1" label="$2"
  hold_ready="$TEST_TMP/$label.ready"
  hold_release="$TEST_TMP/$label.release"
  rm -f "$hold_ready" "$hold_release"
  bash -c '
    exec 8>"$1"
    flock -n 8
    touch "$2"
    while [ ! -e "$3" ]; do sleep 1; done
  ' _ "$lock" "$hold_ready" "$hold_release" &
  holder=$!
  for _ in 1 2 3 4 5; do [ -e "$hold_ready" ] && break; sleep 1; done
  [ -e "$hold_ready" ]
}

stop_holder() {
  touch "$hold_release"
  wait "$holder"
}

load_main_lock
acquire_lock
[ "$LOCK_ACQUIRED" = 1 ]
[ -f "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ]
if flock -n "$LOCK_DIR" -c true; then
  echo "main project lock was not held" >&2
  exit 1
fi
release_lock
[ -f "$LOCK_DIR" ]
flock -n "$LOCK_DIR" -c true

rm -f "$LOCK_DIR"
mkdir "$LOCK_DIR"
printf '99999999\n' >"$LOCK_DIR/pid"
acquire_lock
[ "$LOCK_ACQUIRED" = 1 ] && [ -f "$LOCK_DIR" ]
release_lock

start_holder "$SIDECAR_SYNC_LOCK" sidecar
rm -f "$TEST_TMP/unexpected-acquire"
(
  load_main_lock
  acquire_lock
  touch "$TEST_TMP/unexpected-acquire"
)
[ ! -e "$TEST_TMP/unexpected-acquire" ] \
  || { echo "main project ignored an active Sidecar lock" >&2; exit 1; }
stop_holder

start_holder "$PASSWALL_OBSERVE_LOCK" observe
rm -f "$TEST_TMP/unexpected-acquire"
(
  load_main_lock
  acquire_lock
  touch "$TEST_TMP/unexpected-acquire"
)
[ ! -e "$TEST_TMP/unexpected-acquire" ] \
  || { echo "main project ignored an active PassWall observation lock" >&2; exit 1; }
stop_holder

load_main_lock
exec 8>"$PASSWALL_OBSERVE_LOCK"
flock -n 8
CFST_PASSWALL_NODE_OBSERVE_OWNER=1 acquire_lock
[ "$LOCK_ACQUIRED" = 1 ]
release_lock
flock -u 8
exec 8>&-

echo "project lock coordination tests passed"
