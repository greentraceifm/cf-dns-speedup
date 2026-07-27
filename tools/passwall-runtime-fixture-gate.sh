#!/bin/sh

set -eu

INPUT=${1:-}
EXPECTED_SHA256=${2:-}
WORK="/tmp/passwall-runtime-fixture-$$"
SYSTEM_TMP=/tmp/etc/passwall
RUNTIME_JSON="$WORK/runtime/fixture-runtime.json"
TEST_LOG="$WORK/xray-test.log"

fail() {
	echo "RUNTIME_FIXTURE_STATUS=failed"
	echo "RUNTIME_FIXTURE_REASON=$1"
	exit 1
}

count_processes() {
	pidof "$1" 2>/dev/null | wc -w
}

count_target_listeners() {
	local count=0 port n
	for port in 1070 1041 11400 15353; do
		n=$(netstat -lntp 2>/dev/null | grep -c ":${port} " || true)
		count=$((count + n))
	done
	echo "$count"
}

cleanup() {
	case "$WORK" in
		/tmp/passwall-runtime-fixture-[0-9]*) rm -rf "$WORK" ;;
	esac
}

trap cleanup EXIT HUP INT TERM

[ "$(id -u)" = "0" ] || fail not_root
[ -n "$INPUT" ] || fail missing_input
[ -n "$EXPECTED_SHA256" ] || fail missing_expected_sha256
[ -f "$INPUT" ] || fail input_not_regular
[ ! -L "$INPUT" ] || fail input_symlink
[ "$(wc -c < "$INPUT")" -le 262144 ] || fail input_too_large

actual_sha256=$(sha256sum "$INPUT" | awk '{print $1}')
[ "$actual_sha256" = "$EXPECTED_SHA256" ] || fail input_hash_mismatch

[ "$(uci -q get passwall.@global[0].enabled)" = "0" ] || fail staging_uci_enabled
if /etc/init.d/passwall enabled >/dev/null 2>&1; then
	fail staging_init_enabled
fi
[ "$(count_processes xray)" = "0" ] || fail preexisting_xray_process
[ "$(count_processes haproxy)" = "0" ] || fail preexisting_haproxy_process
[ "$(count_target_listeners)" = "0" ] || fail preexisting_target_listener
[ ! -e "$SYSTEM_TMP" ] || fail preexisting_system_passwall_tmp
[ ! -e "$WORK" ] || fail work_path_exists

umask 077
mkdir -p "$WORK/conf" "$WORK/bin" "$WORK/lua/luci/passwall" "$WORK/runtime"
chmod 700 "$WORK" "$WORK/conf" "$WORK/bin" "$WORK/lua" "$WORK/lua/luci" "$WORK/lua/luci/passwall" "$WORK/runtime"
cp "$INPUT" "$WORK/conf/passwall"
chmod 600 "$WORK/conf/passwall"

/sbin/uci -q -c "$WORK/conf" set passwall.@global[0].enabled=0
/sbin/uci -q -c "$WORK/conf" set passwall.node_a.protocol='vmess'
/sbin/uci -q -c "$WORK/conf" delete passwall.node_a.alpn
/sbin/uci -q -c "$WORK/conf" set passwall.node_a.alpn='h2,http/1.1'
/sbin/uci -q -c "$WORK/conf" commit passwall
[ "$(/sbin/uci -q -c "$WORK/conf" get passwall.@global[0].enabled)" = "0" ] || fail isolated_config_not_disabled
[ -n "$(/sbin/uci -q -c "$WORK/conf" get passwall.node_a.protocol)" ] || fail fixture_node_missing

cat > "$WORK/bin/uci" <<'EOF'
#!/bin/sh
exec /sbin/uci -c "$PASSWALL_ISOLATED_UCI_DIR" "$@"
EOF
chmod 700 "$WORK/bin/uci"

sed \
	-e 's#uci = require "luci.model.uci".cursor()#uci = require "uci".cursor(os.getenv("PASSWALL_ISOLATED_UCI_DIR"))#' \
	-e 's#CACHE_PATH = "/tmp/etc/" .. appname .. "_tmp"#CACHE_PATH = os.getenv("PASSWALL_ISOLATED_WORK") .. "/cache"#' \
	-e 's#LOG_FILE = "/tmp/log/" .. appname .. ".log"#LOG_FILE = os.getenv("PASSWALL_ISOLATED_WORK") .. "/passwall.log"#' \
	-e 's#TMP_PATH = "/tmp/etc/" .. appname#TMP_PATH = os.getenv("PASSWALL_ISOLATED_WORK") .. "/runtime"#' \
	/usr/lib/lua/luci/passwall/api.lua > "$WORK/lua/luci/passwall/api.lua"
sed -i '/local value = uci:get_first(appname, type, config, default)/c\
\tlocal value\
\tuci:foreach(appname, type, function(section)\
\t\tif value == nil then value = section[config] end\
\tend)' "$WORK/lua/luci/passwall/api.lua"
chmod 600 "$WORK/lua/luci/passwall/api.lua"
grep -Fq 'require "uci".cursor(os.getenv("PASSWALL_ISOLATED_UCI_DIR"))' "$WORK/lua/luci/passwall/api.lua" || fail lua_cursor_patch_failed
if grep -Fq 'uci:get_first(appname, type, config, default)' "$WORK/lua/luci/passwall/api.lua"; then
	fail lua_get_first_patch_failed
fi

sed 's#^\. /usr/share/passwall/utils.sh$#. "${PASSWALL_ISOLATED_WORK}/utils.sh"#' \
	/usr/share/passwall/app.sh > "$WORK/app.sh"
sed \
	-e 's#^TMP_PATH=/tmp/etc/${CONFIG}$#TMP_PATH=${PASSWALL_ISOLATED_WORK}/runtime#' \
	-e 's#^LOG_FILE=/tmp/log/${CONFIG}.log$#LOG_FILE=${PASSWALL_ISOLATED_WORK}/passwall.log#' \
	/usr/share/passwall/utils.sh > "$WORK/utils.sh"
chmod 700 "$WORK/app.sh" "$WORK/utils.sh"
grep -Fq '. "${PASSWALL_ISOLATED_WORK}/utils.sh"' "$WORK/app.sh" || fail app_source_patch_failed
grep -Fq 'TMP_PATH=${PASSWALL_ISOLATED_WORK}/runtime' "$WORK/utils.sh" || fail utils_tmp_patch_failed

export PASSWALL_ISOLATED_WORK="$WORK"
export PASSWALL_ISOLATED_UCI_DIR="$WORK/conf"
export PATH="$WORK/bin:$PATH"
export LUA_PATH="$WORK/lua/?.lua;$WORK/lua/?/init.lua;;"

[ "$(uci -q get passwall.@global[0].enabled)" = "0" ] || fail shell_uci_isolation_failed
lua -e 'local api=require "luci.passwall.api"; local v=api.uci:get("passwall", "node_a", "protocol"); os.exit(v and 0 or 1)' \
	|| fail lua_uci_isolation_failed

set +e
"$WORK/app.sh" run_socks \
	flag=fixture \
	node=node_a \
	bind=127.0.0.1 \
	socks_port=19080 \
	config_file=fixture-runtime.json \
	no_run=1 >/dev/null 2>&1
generation_rc=$?
set -e
case "$generation_rc" in
	0|1) ;;
	*) fail passwall_no_run_generation_failed ;;
esac

[ -s "$RUNTIME_JSON" ] || fail runtime_json_missing
chmod 600 "$RUNTIME_JSON"

/usr/bin/xray run -test -c "$RUNTIME_JSON" > "$TEST_LOG" 2>&1 || fail installed_xray_test_failed

[ "$(count_processes xray)" = "0" ] || fail xray_process_started
[ "$(count_processes haproxy)" = "0" ] || fail haproxy_process_started
[ "$(count_target_listeners)" = "0" ] || fail target_listener_started
[ ! -e "$SYSTEM_TMP" ] || fail system_passwall_tmp_created
[ "$(uci -q get passwall.@global[0].enabled)" = "0" ] || fail staging_uci_changed
if /etc/init.d/passwall enabled >/dev/null 2>&1; then
	fail staging_init_changed
fi

echo "RUNTIME_FIXTURE_STATUS=success"
echo "RUNTIME_FIXTURE_BYTES=$(wc -c < "$RUNTIME_JSON")"
echo "RUNTIME_FIXTURE_XRAY_VERSION=$(/usr/bin/xray version 2>/dev/null | sed -n '1s/^Xray //p' | awk '{print $1}')"
echo "RUNTIME_FIXTURE_GENERATOR_RC=$generation_rc"
echo "RUNTIME_FIXTURE_XRAY_TEST=success"
echo "RUNTIME_FIXTURE_XRAY_PROCS=0"
echo "RUNTIME_FIXTURE_HAPROXY_PROCS=0"
echo "RUNTIME_FIXTURE_TARGET_LISTENERS=0"
echo "RUNTIME_FIXTURE_SYSTEM_TMP=absent"
