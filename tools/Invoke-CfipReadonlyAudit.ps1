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

$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$identity = Join-Path $env:USERPROFILE '.ssh\openclaw_ubuntu_20261003'
$knownHosts = Join-Path $env:USERPROFILE '.ssh\known_hosts'
$openClaw = 'ubuntu@192.168.1.140'
$sidecarTool = '/home/ubuntu/.openclaw/tools/cfip-maintenance-readonly.sh'
$vm36Tool = '/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh'

foreach ($path in @($identity, $knownHosts)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required local SSH file is missing: $path"
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

function Invoke-OpenClawCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteCommand
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $result = @(& $ssh @sshOptions $openClaw $RemoteCommand 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $result | ForEach-Object { Write-Output "$_" }
    if ($exitCode -ne 0) {
        throw "OpenClaw command failed with exit code $exitCode. Stopped without credential fallback."
    }
}

Write-Output '=== .110 fixed read-only audit ==='
Invoke-OpenClawCommand $sidecarTool

Write-Output '=== VM36 protected-key preflight ==='
Invoke-OpenClawCommand "$vm36Tool --check"

$remoteAudit = @'
set -eu
umask 077
APP=/root/cf-dns-speedup
printf 'VM36_TIME='; date '+%F %T %z'
printf 'SYNC_REPORT_BEGIN\n'
if [ -r "$APP/sidecar-auto-sync.latest.tsv" ]; then cat "$APP/sidecar-auto-sync.latest.tsv"; else echo MISSING; fi
printf 'SYNC_REPORT_END\n'
printf 'SYNC_LOG_LAST='
tail -n 1 "$APP/sidecar-auto-sync.log" 2>/dev/null || true
printf 'CRON_BEGIN\n'
crontab -l 2>/dev/null | grep -E 'sidecar-auto-sync|06:30' || true
printf 'CRON_END\n'
printf 'APPLY_FLAGS_BEGIN\n'
sed -n -E '/^(CFIP_AUTO_SYNC_APPLY|CFIP_AUTO_SYNC_COMPETITION_APPLY|CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY)=/p' "$APP/sidecar-auto-sync.env" 2>/dev/null | tail -n 10
printf 'APPLY_FLAGS_END\n'
printf 'LOCKS_BEGIN\n'
for lock in /tmp/cfip-sidecar-auto-sync.lock /tmp/cfip-candidate-gate.lock /tmp/cf-dns-speedup.lock /tmp/cf-dns-speedup-passwall-node-observe.lock; do
    if [ ! -e "$lock" ]; then
        printf '%s=absent\n' "$lock"
    elif command -v flock >/dev/null 2>&1 && flock -n "$lock" -c true; then
        printf '%s=free\n' "$lock"
    else
        printf '%s=present_or_busy\n' "$lock"
    fi
done
printf 'LOCKS_END\n'
printf 'XRAY_PROCESSES_BEGIN\n'
ps w | grep '[x]ray' || true
printf 'XRAY_PROCESSES_END\n'
for port in 1070 1041 11400 15353; do
    if netstat -lnptu 2>/dev/null | grep -Eq "[:.]$port[[:space:]]"; then
        printf 'LISTEN_%s=yes\n' "$port"
    else
        printf 'LISTEN_%s=no\n' "$port"
    fi
done
for name in auto.greentraceifm.top auto1.greentraceifm.top auto2.greentraceifm.top auto3.greentraceifm.top auto4.greentraceifm.top; do
    printf 'DNS %s' "$name"
    for server in 127.0.0.1 192.168.1.1 1.1.1.1; do
        answer=NO_ANSWER
        attempt=1
        while [ "$attempt" -le 3 ]; do
            candidate=$(nslookup "$name" "$server" 2>&1 | awk '
                /^Name:[[:space:]]/ {seen_name=1; next}
                seen_name && /^Address([[:space:]][0-9]+)?:[[:space:]]/ {
                    sub(/^Address([[:space:]][0-9]+)?:[[:space:]]*/, "", $0)
                    print
                    exit
                }
            ')
            if [ -n "$candidate" ]; then
                answer=$candidate
                break
            fi
            sleep 1
            attempt=$((attempt + 1))
        done
        printf ' | %s=%s' "$server" "$answer"
    done
    printf '\n'
done
for url in https://www.google.com/generate_204 https://www.youtube.com/generate_204; do
    printf 'DEFAULT_HTTP %s=' "$url"
    curl -L -sS -o /dev/null --connect-timeout 8 --max-time 15 -w '%{http_code}\n' "$url" 2>/dev/null || true
    printf 'SOCKS_HTTP %s=' "$url"
    curl --socks5-hostname 127.0.0.1:1070 -L -sS -o /dev/null --connect-timeout 8 --max-time 15 -w '%{http_code}\n' "$url" 2>/dev/null || true
done
printf 'CFIP_RESIDUALS_BEGIN\n'
ps w | grep -E '[c]f-dns-speedup|[s]idecar-auto-sync|[r]outer-candidate-gate|[p]asswall-node-observe' || true
printf 'CFIP_RESIDUALS_END\n'
'@

$payload = [Convert]::ToBase64String($utf8.GetBytes($remoteAudit))
$remoteCommand = "printf '%s' '$payload' | base64 -d | $vm36Tool --stdin"
Write-Output '=== VM36 read-only runtime audit ==='
Invoke-OpenClawCommand $remoteCommand
