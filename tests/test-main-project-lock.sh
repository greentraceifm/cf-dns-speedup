#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
HAVE_REAL_FLOCK=1
if ! command -v flock >/dev/null 2>&1; then
  HAVE_REAL_FLOCK=0
  mkdir -p "$TEST_TMP/bin"
  cat >"$TEST_TMP/bin/flock" <<'EOF'
#!/usr/bin/env sh
[ "${MOCK_FLOCK_BUSY:-0}" != 1 ]
EOF
  chmod +x "$TEST_TMP/bin/flock"
  export PATH="$TEST_TMP/bin:$PATH"
fi

verify_lock_semantics() {
  local script="$1" lock="$TEST_TMP/project.lock"
  rm -rf "$lock"

  # shellcheck disable=SC1090
  . "$script"

  if main_project_lock_busy "$lock"; then
    echo "absent main project lock was reported busy: $script" >&2
    exit 1
  fi

  : >"$lock"
  if main_project_lock_busy "$lock"; then
    echo "free regular main project lock was reported busy: $script" >&2
    exit 1
  fi

  if [ "$HAVE_REAL_FLOCK" -eq 1 ]; then
    exec 8>"$lock"
    flock -n 8
  else
    export MOCK_FLOCK_BUSY=1
  fi
  if ! main_project_lock_busy "$lock"; then
    echo "actively locked main project file was reported free: $script" >&2
    exit 1
  fi
  if [ "$HAVE_REAL_FLOCK" -eq 1 ]; then
    flock -u 8
    exec 8>&-
  else
    unset MOCK_FLOCK_BUSY
  fi

  rm -f "$lock"
  mkdir "$lock"
  if ! main_project_lock_busy "$lock"; then
    echo "legacy directory main project lock was reported free: $script" >&2
    exit 1
  fi
  rmdir "$lock"

  : >"$TEST_TMP/symlink-target"
  ln -s "$TEST_TMP/symlink-target" "$lock"
  if [ -L "$lock" ]; then
    if ! main_project_lock_busy "$lock"; then
      echo "symlink main project lock was reported free: $script" >&2
      exit 1
    fi
  fi
  rm -f "$lock" "$TEST_TMP/symlink-target"

  if ln -s "$TEST_TMP/missing-target" "$lock" 2>/dev/null; then
    if ! main_project_lock_busy "$lock"; then
      echo "dangling symlink main project lock was reported free: $script" >&2
      exit 1
    fi
  fi
  rm -f "$lock"
}

verify_lock_semantics "$ROOT/sidecar-auto-sync.sh"
verify_lock_semantics "$ROOT/router-candidate-gate.sh"

echo "main project lock semantics tests passed"
