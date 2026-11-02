$TestOnly = $args -contains '--test-only'
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sidecar = Join-Path $root 'sidecar-auto-sync.sh'
$speedup = Join-Path $root 'cf-dns-speedup.sh'
$gate = Join-Path $root 'router-candidate-gate.sh'
$test = Join-Path $root 'tests\test-sidecar-auto-sync-plan.sh'
$identity = Join-Path $env:USERPROFILE '.ssh\openclaw_ubuntu_20261003'
$knownHosts = Join-Path $env:USERPROFILE '.ssh\known_hosts'
$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$scp = (Get-Command scp.exe -ErrorAction Stop).Source
$openClaw = 'ubuntu@192.168.1.140'
$vm36Tool = '/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh'

foreach ($path in @($sidecar, $speedup, $gate, $test, $identity, $knownHosts)) {
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

foreach ($path in @($sidecar, $speedup, $test)) {
    Write-Output "$(Split-Path -Leaf $path)=$(Get-Sha256 $path)"
}

$check = @(& $ssh @sshOptions $openClaw "$vm36Tool --check" 2>&1)
if ($LASTEXITCODE -ne 0 -or ($check -notmatch 'VM36_KEY_AUTH=PASS')) {
    $check | ForEach-Object { Write-Output "$_" }
    throw 'VM36 protected-key preflight failed; no production change was attempted.'
}
$check | ForEach-Object { Write-Output "$_" }

function Invoke-RemotePayload([string]$Text) {
    $localPayload = Join-Path $env:TEMP ("cfip-primary-repair-" + [guid]::NewGuid().ToString('N') + '.sh')
    $remotePayload = '/tmp/cfip-primary-repair-' + [guid]::NewGuid().ToString('N') + '.sh'
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        [IO.File]::WriteAllBytes($localPayload, [Text.Encoding]::ASCII.GetBytes($Text))
        $scpArgs = $sshOptions + @($localPayload, ("{0}:{1}" -f $openClaw, $remotePayload))
        $scpOutput = @(& $scp @scpArgs 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $scpOutput | ForEach-Object { Write-Output "$_" }
            throw 'Upload to .140 failed; VM36 was not contacted.'
        }
        $remoteCommand = "cat '$remotePayload' | $vm36Tool --stdin; rc=`$?; rm -f '$remotePayload'; exit `$rc"
        $output = @(& $ssh @sshOptions $openClaw $remoteCommand 2>&1)
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Output "$_" }
        if ($exitCode -ne 0) {
            throw "VM36 fixed-entry command failed with exit code $exitCode."
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Remove-Item -LiteralPath $localPayload -Force -ErrorAction SilentlyContinue
        & $ssh @sshOptions $openClaw "rm -f '$remotePayload'" 2>$null | Out-Null
    }
}

$sidecarB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($sidecar))
$speedupB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($speedup))
$gateB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($gate))
$testB64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($test))

if ($TestOnly) {
    $testRemote = @'
set -eu
umask 077
app=/root/cf-dns-speedup
stage=/tmp/cfip-primary-repair-test
trap 'rm -rf "$stage"' EXIT INT TERM
test "$(sha256sum "$app/sidecar-auto-sync.sh" | awk '{print $1}')" = '__SIDECAR_SHA__'
test "$(sha256sum "$app/cf-dns-speedup.sh" | awk '{print $1}')" = '__SPEEDUP_SHA__'
mkdir -p "$stage/tests"
chmod 700 "$stage" "$stage/tests"
printf '%s' '__SIDECAR_B64__' | base64 -d >"$stage/sidecar-auto-sync.sh"
printf '%s' '__GATE_B64__' | base64 -d >"$stage/router-candidate-gate.sh"
printf '%s' '__TEST_B64__' | base64 -d >"$stage/tests/test-sidecar-auto-sync-plan.sh"
chmod 700 "$stage/sidecar-auto-sync.sh" "$stage/router-candidate-gate.sh"
chmod 700 "$stage/tests/test-sidecar-auto-sync-plan.sh"
bash -n "$stage/sidecar-auto-sync.sh"
bash -n "$stage/router-candidate-gate.sh"
bash "$stage/tests/test-sidecar-auto-sync-plan.sh"
echo VM36_PRIMARY_REPAIR_BUSYBOX_TEST=PASS
'@
    $testRemote = $testRemote.Replace('__SIDECAR_SHA__', (Get-Sha256 $sidecar))
    $testRemote = $testRemote.Replace('__SPEEDUP_SHA__', (Get-Sha256 $speedup))
    $testRemote = $testRemote.Replace('__SIDECAR_B64__', $sidecarB64)
    $testRemote = $testRemote.Replace('__GATE_B64__', $gateB64)
    $testRemote = $testRemote.Replace('__TEST_B64__', $testB64)
    $testRemote = $testRemote.TrimStart([char]0xFEFF, [char]0x0D, [char]0x0A)

    Invoke-RemotePayload $testRemote
    exit 0
}

$remote = @'
set -eu
umask 077

app=/root/cf-dns-speedup
stage=/tmp/cfip-primary-repair-stage
backup=""
installed=0

cleanup() {
  rm -rf "$stage"
}

rollback() {
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$installed" -eq 1 ] && [ -n "$backup" ]; then
    cp -p "$backup/sidecar-auto-sync.sh" "$app/sidecar-auto-sync.sh"
    cp -p "$backup/cf-dns-speedup.sh" "$app/cf-dns-speedup.sh"
    chmod 700 "$app/sidecar-auto-sync.sh" "$app/cf-dns-speedup.sh"
    echo "VM36_PRIMARY_REPAIR_ROLLBACK=$backup" >&2
  fi
  cleanup
  exit "$rc"
}
trap rollback EXIT INT TERM

test -d "$app"
rm -rf "$stage"
mkdir -p "$stage/tests"
chmod 700 "$stage" "$stage/tests"
printf '%s' '__SIDECAR_B64__' | base64 -d >"$stage/sidecar-auto-sync.sh"
printf '%s' '__SPEEDUP_B64__' | base64 -d >"$stage/cf-dns-speedup.sh"
printf '%s' '__GATE_B64__' | base64 -d >"$stage/router-candidate-gate.sh"
printf '%s' '__TEST_B64__' | base64 -d >"$stage/tests/test-sidecar-auto-sync-plan.sh"
chmod 700 "$stage/sidecar-auto-sync.sh" "$stage/cf-dns-speedup.sh" "$stage/router-candidate-gate.sh"
chmod 700 "$stage/tests/test-sidecar-auto-sync-plan.sh"

snapshot_xray_pids() {
  pidof xray 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -n
}
snapshot_xray_listeners() {
  netstat -lntp 2>/dev/null | awk 'NR > 2 && /xray/ {print $4 "|" $7}' | sort
}
http_gate() {
  test "$(curl -4 -L -sS -o /dev/null --connect-timeout 8 --max-time 15 -w '%{http_code}' https://www.google.com/generate_204)" = 204
  test "$(curl -4 -L -sS -o /dev/null --connect-timeout 8 --max-time 15 -w '%{http_code}' https://www.youtube.com/generate_204)" = 204
}
copy_optional() {
  source="$1"
  destination="$2"
  test ! -e "$source" || cp -p "$source" "$destination"
}

exec 7>/tmp/cf-dns-speedup.lock
flock -n 7
exec 8>/tmp/cfip-candidate-gate.lock
flock -n 8
exec 9>/tmp/cfip-sidecar-auto-sync.lock
flock -n 9

baseline_pids="$(snapshot_xray_pids)"
baseline_listeners="$(snapshot_xray_listeners)"
baseline_passwall="$(sha256sum /etc/config/passwall | awk '{print $1}')"
baseline_cron="$( (crontab -l 2>/dev/null || true) | sha256sum | awk '{print $1}')"
test -n "$baseline_pids"
test -n "$baseline_listeners"
for port in 1070 1041 11400 15353; do
  netstat -lntp 2>/dev/null | grep -Eq "[:.]$port[[:space:]]"
done
http_gate
echo "VM36_PRIMARY_REPAIR_STEP=runtime_gate_ok"

bash -n "$stage/sidecar-auto-sync.sh"
bash -n "$stage/cf-dns-speedup.sh"
bash "$stage/tests/test-sidecar-auto-sync-plan.sh"
echo "VM36_PRIMARY_REPAIR_STEP=stage_tests_ok"

backup="/root/openwrt-backup/cfip-primary-repair-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
chmod 700 "$backup"
cp -p "$app/sidecar-auto-sync.sh" "$backup/sidecar-auto-sync.sh"
cp -p "$app/cf-dns-speedup.sh" "$backup/cf-dns-speedup.sh"
copy_optional "$app/sidecar-auto-sync.env" "$backup/sidecar-auto-sync.env"
(crontab -l 2>/dev/null || true) >"$backup/crontab.txt"
for state in \
  sidecar-auto-sync.latest.tsv sidecar-auto-sync-history.tsv sidecar-auto-sync.state \
  router-primary-canary-history.tsv router-primary-canary.latest.tsv \
  router-primary-baseline-qualified.tsv router-candidate-competition-qualified.tsv; do
  copy_optional "$app/$state" "$backup/$state"
done
chmod 600 "$backup"/*
sha256sum "$backup"/* >"$backup/SHA256SUMS"
sha256sum -c "$backup/SHA256SUMS" >/dev/null
echo "VM36_PRIMARY_REPAIR_STEP=backup_ok"

cp -p "$stage/sidecar-auto-sync.sh" "$app/sidecar-auto-sync.sh.new"
cp -p "$stage/cf-dns-speedup.sh" "$app/cf-dns-speedup.sh.new"
chmod 700 "$app/sidecar-auto-sync.sh.new" "$app/cf-dns-speedup.sh.new"
mv -f "$app/sidecar-auto-sync.sh.new" "$app/sidecar-auto-sync.sh"
mv -f "$app/cf-dns-speedup.sh.new" "$app/cf-dns-speedup.sh"
installed=1

test "$(sha256sum "$app/sidecar-auto-sync.sh" | awk '{print $1}')" = "__SIDECAR_SHA__"
test "$(sha256sum "$app/cf-dns-speedup.sh" | awk '{print $1}')" = "__SPEEDUP_SHA__"
bash -n "$app/sidecar-auto-sync.sh"
bash -n "$app/cf-dns-speedup.sh"
test "$(snapshot_xray_pids)" = "$baseline_pids"
test "$(snapshot_xray_listeners)" = "$baseline_listeners"
test "$(sha256sum /etc/config/passwall | awk '{print $1}')" = "$baseline_passwall"
test "$( (crontab -l 2>/dev/null || true) | sha256sum | awk '{print $1}')" = "$baseline_cron"
for port in 1070 1041 11400 15353; do
  netstat -lntp 2>/dev/null | grep -Eq "[:.]$port[[:space:]]"
done
http_gate

topology_tmp="$stage/passwall-node-topology.tsv"
APP_DIR="$app" PASSWALL_NODE_TOPOLOGY_FILE="$topology_tmp" \
  "$app/cf-dns-speedup.sh" passwall-node-topology >/dev/null
test -s "$topology_tmp"
grep -Eq '^global\t' "$topology_tmp"

installed=0
echo "VM36_PRIMARY_REPAIR=PASS"
echo "VM36_PRIMARY_REPAIR_BACKUP=$backup"
echo "VM36_PRIMARY_REPAIR_SIDEcar_SHA=__SIDECAR_SHA__"
echo "VM36_PRIMARY_REPAIR_SPEEDUP_SHA=__SPEEDUP_SHA__"
echo "VM36_PASSWALL_RESTART=0"
echo "VM36_CRON_CHANGED=0"
echo "VM36_CLOUDFLARE_WRITE=0"
echo "VM36_DNS_CHANGED=0"
'@

$remote = $remote.Replace('__SIDECAR_B64__', $sidecarB64)
$remote = $remote.Replace('__SPEEDUP_B64__', $speedupB64)
$remote = $remote.Replace('__GATE_B64__', $gateB64)
$remote = $remote.Replace('__TEST_B64__', $testB64)
$remote = $remote.Replace('__SIDECAR_SHA__', (Get-Sha256 $sidecar))
$remote = $remote.Replace('__SPEEDUP_SHA__', (Get-Sha256 $speedup))
$remote = $remote.TrimStart([char]0xFEFF, [char]0x0D, [char]0x0A)

Invoke-RemotePayload $remote
