#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'kill "$FAKE_EXISTING_PID" 2>/dev/null || true; rm -rf "$TMP_DIR" /tmp/cfip-router-canary.*' EXIT
BIN="$TMP_DIR/bin"
mkdir -p "$BIN" "$TMP_DIR/app/candidate-staging"

cat > "$BIN/flock" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
cat > "$BIN/pidof" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "$FAKE_EXISTING_PID"
EOF
cat > "$BIN/netstat" <<'EOF'
#!/usr/bin/env sh
printf 'Active Internet connections (only servers)\n'
printf 'Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name\n'
printf 'tcp        0      0 127.0.0.1:1070          0.0.0.0:*               LISTEN      %s/xray\n' "$FAKE_EXISTING_PID"
EOF
cat > "$BIN/jq" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  -e) exit 0 ;;
  -r) printf 'proxy\n' ;;
  *) printf '{"log":{"loglevel":"warning"},"inbounds":[],"outbounds":[{"protocol":"vmess","tag":"proxy","settings":{"address":"104.17.1.10"}}],"routing":{}}\n' ;;
esac
EOF
cat > "$BIN/fake-xray" <<'EOF'
#!/usr/bin/env sh
if [ "${2:-}" = "-test" ]; then exit 0; fi
exit 0
EOF
chmod +x "$BIN"/*
printf 'config passwall\n' > "$TMP_DIR/passwall"
printf '{"outbounds":[{"protocol":"vmess","tag":"proxy","settings":{"address":"104.17.1.10"}}]}\n' > "$TMP_DIR/runtime.json"
NOW="$(date +%s)"
OBSERVED_AT="$(date '+%F %T')"
HEADER=$'schema_version\texported_epoch\tobserved_at\tcandidate_ip\tdirect_MBps\tround1_MBps\tround2_MBps\tmin_MBps\tavg_MBps\thttp1\thttp2\tstatus\tpath_mode'
{
  printf '%s\n' "$HEADER"
  printf 'cfip-sidecar-candidates-v1\t%s\t%s\t104.17.1.10\t9.00\t6.80\t6.70\t6.70\t6.75\t200\t200\tpass\tsidecar_proxy\n' "$NOW" "$OBSERVED_AT"
} > "$TMP_DIR/export.tsv"

sleep 60 &
FAKE_EXISTING_PID=$!
export FAKE_EXISTING_PID
export PATH="$BIN:$PATH"
export APP_DIR="$TMP_DIR/app"
export CONFIG_FILE="$TMP_DIR/missing.env"
export CFIP_CANDIDATE_GATE_LOCK="$TMP_DIR/gate.lock"
export CFIP_ROUTER_CANARY_XRAY_BIN="$BIN/fake-xray"
export CFIP_ROUTER_CANARY_RUNTIME_JSON="$TMP_DIR/runtime.json"
export CFIP_ROUTER_CANARY_PASSWALL_CONFIG="$TMP_DIR/passwall"
export CFIP_ROUTER_CANARY_PORT=19080

bash "$ROOT/router-candidate-gate.sh" import "$TMP_DIR/export.tsv" >/dev/null
bash "$ROOT/router-candidate-gate.sh" canary-plan 104.17.1.10 | grep -q 'canary_plan=ok'
[ "$(kill -0 "$FAKE_EXISTING_PID" 2>/dev/null; echo $?)" = 0 ] \
  || { echo "existing process was changed by canary plan" >&2; exit 1; }
if find /tmp -maxdepth 1 -type d -name 'cfip-router-canary.*' | grep -q .; then
  echo "canary plan left a temporary config directory" >&2
  exit 1
fi

echo "router canary plan test passed"
