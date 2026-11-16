$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
try { chcp 65001 > $null } catch {}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8
$OutputEncoding = $utf8
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$testOnly = $args -contains '--test-only'
$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root 'sidecar-auto-sync.sh'
$gatePath = Join-Path $root 'router-candidate-gate.sh'
$testPath = Join-Path $root 'tests\test-sidecar-auto-sync-plan.sh'
$identity = Join-Path $env:USERPROFILE '.ssh\openclaw_ubuntu_20261003'
$knownHosts = Join-Path $env:USERPROFILE '.ssh\known_hosts'
$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$scp = (Get-Command scp.exe -ErrorAction Stop).Source
$openClaw = 'ubuntu@192.168.1.140'
$vm36Tool = '/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh'
$expectedOldScript = '6e1d4dc429f4c84135503325e94fdb2549f5a5359c1e541f3fc8633e2fa2a963'
$expectedSpeedup = '3fcdec7a6eb1c0da699b42fc8efce2abde61500c449b072c87431504c0c4b76b'
$expectedGate = 'f0a9153f574e0c807cf3873eb00d07eb0b8c482b75264e2450aec9f9b12e90ec'

foreach ($path in @($scriptPath, $gatePath, $testPath, $identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required file is missing: $path"
    }
}

$sshOptions = @(
    '-F', 'NUL',
    '-i', $identity,
    '-o', 'IdentitiesOnly=yes',
    '-o', 'BatchMode=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', "UserKnownHostsFile=$knownHosts",
    '-o', 'ConnectTimeout=10'
)

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$newScriptSha = Get-Sha256 $scriptPath
Write-Output "sidecar-auto-sync.sh=$newScriptSha"
if ((Get-FileHash -LiteralPath $testPath -Algorithm SHA256).Hash -eq '') {
    throw 'Could not hash the plan test.'
}

$check = @(& $ssh @sshOptions $openClaw "$vm36Tool --check" 2>&1)
if ($LASTEXITCODE -ne 0 -or ($check -notmatch 'VM36_KEY_AUTH=PASS')) {
    $check | ForEach-Object { Write-Output "$_" }
    throw 'VM36 protected-key preflight failed; no production change was attempted.'
}
$check | ForEach-Object { Write-Output "$_" }

$scriptB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($scriptPath))
$gateB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($gatePath))
$testB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($testPath))
$remote = @'
set -eu
umask 077
app=/root/cf-dns-speedup
stage="$(mktemp -d /tmp/cfip-global-dedupe.XXXXXX)"
backup=""
installed=0
trap 'rc=$?; echo "CFIP_GLOBAL_DEDUPE_FAIL_LINE=${LINENO} RC=$rc" >&2' ERR

cleanup() {
  case "$stage" in /tmp/cfip-global-dedupe.*) rm -rf "$stage" ;; *) return 1 ;; esac
}
rollback_on_failure() {
  rc=$?
  trap - EXIT
  if [ "$rc" -ne 0 ] && [ "$installed" -eq 1 ] && [ -n "$backup" ]; then
    cp -p "$backup/sidecar-auto-sync.sh" "$app/sidecar-auto-sync.sh"
    chmod 700 "$app/sidecar-auto-sync.sh"
    echo "CFIP_GLOBAL_DEDUPE_ROLLBACK=restored" >&2
  fi
  cleanup
  exit "$rc"
}
trap rollback_on_failure EXIT INT TERM

mkdir -p "$stage/tests"
chmod 700 "$stage" "$stage/tests"
printf '%s' '__SCRIPT_B64__' | base64 -d >"$stage/sidecar-auto-sync.sh"
printf '%s' '__GATE_B64__' | base64 -d >"$stage/router-candidate-gate.sh"
printf '%s' '__TEST_B64__' | base64 -d >"$stage/tests/test-sidecar-auto-sync-plan.sh"
chmod 700 "$stage/sidecar-auto-sync.sh" "$stage/router-candidate-gate.sh" "$stage/tests/test-sidecar-auto-sync-plan.sh"

test "$(sha256sum "$app/sidecar-auto-sync.sh" | awk '{print $1}')" = '__OLD_SCRIPT_SHA__'
test "$(sha256sum "$app/cf-dns-speedup.sh" | awk '{print $1}')" = '__SPEEDUP_SHA__'
test "$(sha256sum "$app/router-candidate-gate.sh" | awk '{print $1}')" = '__GATE_SHA__'
test "$(sha256sum "$stage/sidecar-auto-sync.sh" | awk '{print $1}')" = '__NEW_SCRIPT_SHA__'
bash -n "$stage/sidecar-auto-sync.sh"
bash "$stage/tests/test-sidecar-auto-sync-plan.sh"

snapshot_pids() { pidof xray 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -n; }
snapshot_listeners() { netstat -lntp 2>/dev/null | awk 'NR > 2 && /xray/ {print $4 "|" $7}' | sort; }
snapshot_dns() {
  for name in auto.greentraceifm.top auto1.greentraceifm.top auto2.greentraceifm.top auto3.greentraceifm.top auto4.greentraceifm.top; do
    for server in 127.0.0.1 192.168.1.1 1.1.1.1; do
      answer=$(nslookup "$name" "$server" 2>&1 | awk '/^Address [0-9]*: / {a=$3} /^Address: / {a=$2} END {if (a != "") print a; else print "NO_ANSWER"}')
      printf '%s\t%s\t%s\n' "$name" "$server" "$answer"
    done
  done
}
http_gate() {
  test "$(curl -4 -L -sS -o /dev/null --connect-timeout 8 --max-time 15 -w '%{http_code}' https://www.google.com/generate_204)" = 204
  test "$(curl -4 -L -sS -o /dev/null --connect-timeout 8 --max-time 15 -w '%{http_code}' https://www.youtube.com/generate_204)" = 204
}

exec 7>/tmp/cf-dns-speedup.lock
flock -n 7
exec 8>/tmp/cfip-candidate-gate.lock
flock -n 8
exec 9>/tmp/cfip-sidecar-auto-sync.lock
flock -n 9

baseline_pids="$(snapshot_pids)"
baseline_listeners="$(snapshot_listeners)"
baseline_passwall="$(sha256sum /etc/config/passwall | awk '{print $1}')"
baseline_cron="$( (crontab -l 2>/dev/null || true) | sha256sum | awk '{print $1}')"
baseline_report="$(sha256sum "$app/sidecar-auto-sync.latest.tsv" | awk '{print $1}')"
snapshot_dns >"$stage/dns.before"
test -n "$baseline_pids"
test -n "$baseline_listeners"
for port in 1070 1041 11400 15353; do
  netstat -lntp 2>/dev/null | grep -Eq "[:.]$port[[:space:]]"
done
http_gate

if [ '__TEST_ONLY__' = 1 ]; then
  echo CFIP_GLOBAL_DEDUPE_BUSYBOX_PLAN_TEST=PASS
  exit 0
fi

backup="/root/openwrt-backup/cfip-global-dedupe-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
chmod 700 "$backup"
cp -p "$app/sidecar-auto-sync.sh" "$backup/sidecar-auto-sync.sh"
chmod 600 "$backup/sidecar-auto-sync.sh"
sha256sum "$backup/sidecar-auto-sync.sh" >"$backup/SHA256SUMS"
sha256sum -c "$backup/SHA256SUMS" >/dev/null

cp -p "$stage/sidecar-auto-sync.sh" "$app/sidecar-auto-sync.sh.new"
chmod 700 "$app/sidecar-auto-sync.sh.new"
test "$(sha256sum "$app/sidecar-auto-sync.sh.new" | awk '{print $1}')" = '__NEW_SCRIPT_SHA__'
mv -f "$app/sidecar-auto-sync.sh.new" "$app/sidecar-auto-sync.sh"
installed=1

bash -n "$app/sidecar-auto-sync.sh"
test "$(sha256sum "$app/sidecar-auto-sync.sh" | awk '{print $1}')" = '__NEW_SCRIPT_SHA__'
test "$(snapshot_pids)" = "$baseline_pids"
test "$(snapshot_listeners)" = "$baseline_listeners"
test "$(sha256sum /etc/config/passwall | awk '{print $1}')" = "$baseline_passwall"
test "$( (crontab -l 2>/dev/null || true) | sha256sum | awk '{print $1}')" = "$baseline_cron"
test "$(sha256sum "$app/sidecar-auto-sync.latest.tsv" | awk '{print $1}')" = "$baseline_report"
snapshot_dns >"$stage/dns.after"
cmp -s "$stage/dns.before" "$stage/dns.after"
http_gate

installed=0
echo CFIP_GLOBAL_DEDUPE_DEPLOY=PASS
echo CFIP_GLOBAL_DEDUPE_BACKUP="$backup"
echo CFIP_GLOBAL_DEDUPE_SCRIPT_SHA='__NEW_SCRIPT_SHA__'
echo CFIP_PASSWALL_RESTARTED=0
echo CFIP_CRON_CHANGED=0
echo CFIP_DNS_CHANGED=0
echo CFIP_CLOUDFLARE_WRITE=0
echo CFIP_SYNC_MANUALLY_RUN=0
'@

$remote = $remote.Replace('__SCRIPT_B64__', $scriptB64)
$remote = $remote.Replace('__GATE_B64__', $gateB64)
$remote = $remote.Replace('__TEST_B64__', $testB64)
$remote = $remote.Replace('__OLD_SCRIPT_SHA__', $expectedOldScript)
$remote = $remote.Replace('__SPEEDUP_SHA__', $expectedSpeedup)
$remote = $remote.Replace('__GATE_SHA__', $expectedGate)
$remote = $remote.Replace('__NEW_SCRIPT_SHA__', $newScriptSha)
$remote = $remote.Replace('__TEST_ONLY__', [int]$testOnly)
$remote = $remote.TrimStart([char]0xFEFF, [char]0x0D, [char]0x0A)

$localPayload = Join-Path $env:TEMP ("cfip-global-dedupe-" + [guid]::NewGuid().ToString('N') + '.sh')
$remotePayload = '/tmp/cfip-global-dedupe-' + [guid]::NewGuid().ToString('N') + '.sh'
try {
    [IO.File]::WriteAllBytes($localPayload, [Text.Encoding]::ASCII.GetBytes($remote))
    $scpArgs = $sshOptions + @($localPayload, ("{0}:{1}" -f $openClaw, $remotePayload))
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $upload = @(& $scp @scpArgs 2>&1)
        $uploadCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($uploadCode -ne 0) {
        $upload | ForEach-Object { Write-Output "$_" }
        throw 'Upload to .140 failed; VM36 was not changed.'
    }
    $command = "cat '$remotePayload' | $vm36Tool --stdin; rc=`$?; rm -f '$remotePayload'; exit `$rc"
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $ssh @sshOptions $openClaw $command 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $output | ForEach-Object { Write-Output "$_" }
    if ($exitCode -ne 0) {
        throw "VM36 fixed-entry command failed with exit code $exitCode."
    }
}
finally {
    Remove-Item -LiteralPath $localPayload -Force -ErrorAction SilentlyContinue
    & $ssh @sshOptions $openClaw "rm -f '$remotePayload'" 2>$null | Out-Null
}
