#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
BIN="$TMP_DIR/bin"
FAKE_EXISTING_PID=""
cleanup() {
  [ -z "$FAKE_EXISTING_PID" ] || kill "$FAKE_EXISTING_PID" 2>/dev/null || true
  rm -rf "$TMP_DIR" /tmp/cfip-router-canary.*
}
trap cleanup EXIT
mkdir -p "$BIN" "$TMP_DIR/app/candidate-staging"

cat > "$BIN/flock" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$BIN/pidof" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$FAKE_EXISTING_PID"
EOF
cat > "$BIN/nice" <<'EOF'
#!/usr/bin/env sh
[ "$1" = "-n" ] && shift 2
exec "$@"
EOF
cat > "$BIN/netstat" <<'EOF'
#!/usr/bin/env sh
printf 'Active Internet connections (only servers)\n'
printf 'Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name\n'
printf 'tcp        0      0 127.0.0.1:1070          0.0.0.0:*               LISTEN      %s/xray\n' "$FAKE_EXISTING_PID"
if [ -s "$FAKE_CANARY_MARKER" ]; then
  printf 'tcp        0      0 127.0.0.1:19080         0.0.0.0:*               LISTEN      %s/xray\n' "$(cat "$FAKE_CANARY_MARKER")"
fi
EOF
cat > "$BIN/jq" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  -e) exit 0 ;;
  -r) printf 'proxy\n' ;;
  *) printf '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"vmess","tag":"proxy","settings":{"address":"104.17.1.10"}}],"routing":{}}\n' ;;
esac
EOF
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env sh
printf '200\t20000000\t4194304\n'
EOF
cat > "$BIN/fake-xray" <<'EOF'
#!/usr/bin/env bash
if [ "${2:-}" = "-test" ]; then exit 0; fi
printf '%s\n' "$$" > "$FAKE_CANARY_MARKER"
trap 'rm -f "$FAKE_CANARY_MARKER"; exit 0' TERM INT EXIT
while :; do sleep 1; done
EOF
chmod +x "$BIN"/*

printf 'config passwall\n' > "$TMP_DIR/passwall"
printf '{"outbounds":[{"protocol":"vmess","tag":"proxy","settings":{"address":"104.17.1.10"}}]}\n' > "$TMP_DIR/runtime.json"
NOW="$(date +%s)"
OBSERVED_AT="$(date '+%F %T')"
HEADER=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode\tcandidate_tier'
{
  printf '%s\n' "$HEADER"
  printf 'cfip-sidecar-candidates-v2\t%s\t%s\t104.17.1.10\t9.00\t4.20\t4.00\t4.00\t4.10\t200\t200\tlow\tsidecar_proxy\tobservation\n' "$NOW" "$OBSERVED_AT"
} > "$TMP_DIR/export.tsv"

sleep 60 &
FAKE_EXISTING_PID=$!
export FAKE_EXISTING_PID
export FAKE_CANARY_MARKER="$TMP_DIR/canary.pid"
export PATH="$BIN:$PATH"
export APP_DIR="$TMP_DIR/app"
export CONFIG_FILE="$TMP_DIR/missing.env"
export CFIP_CANDIDATE_GATE_LOCK="$TMP_DIR/gate.lock"
export CFST_PASSWALL_NODE_OBSERVE_LOCK="$TMP_DIR/observe.lock"
export CFIP_ROUTER_CANARY_XRAY_BIN="$BIN/fake-xray"
export CFIP_ROUTER_CANARY_RUNTIME_JSON="$TMP_DIR/runtime.json"
export CFIP_ROUTER_CANARY_PASSWALL_CONFIG="$TMP_DIR/passwall"
export CFIP_ROUTER_CANARY_PORT=19080

bash "$ROOT/router-candidate-gate.sh" import "$TMP_DIR/export.tsv" >/dev/null
bash "$ROOT/router-candidate-gate.sh" canary 104.17.1.10 > "$TMP_DIR/canary.out"
grep -q 'min=4.00MB/s status=pass' "$TMP_DIR/canary.out"
awk -F '\t' 'NR == 2 && $2 == "104.17.1.10" && $6 == "4.00" && $12 == "pass" {found=1} END {exit found ? 0 : 1}' \
  "$APP_DIR/router-candidate-canary.latest.tsv"
kill -0 "$FAKE_EXISTING_PID" 2>/dev/null || { echo "existing Xray process was stopped" >&2; exit 1; }
[ ! -e "$FAKE_CANARY_MARKER" ] || { echo "isolated Xray marker remains" >&2; exit 1; }
if find /tmp -maxdepth 1 -type d -name 'cfip-router-canary.*' | grep -q .; then
  echo "isolated canary left a temporary credential directory" >&2
  exit 1
fi

echo "router canary mock test passed"
