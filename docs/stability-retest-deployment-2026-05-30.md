# Stability Retest Deployment - 2026-05-30

## Summary

Production now uses a two-stage selection profile for the OpenWrt Cloudflare preferred IP project:

1. CloudflareSpeedTest does the coarse candidate sweep against the 20MB Cloudflare Pages file.
2. The script retests the top candidates with real `curl --resolve` downloads, then ranks by worst-round throughput first and average throughput second.

This was added because a single high CloudflareSpeedTest result can be a transient peak. On 2026-05-30, `172.67.79.2` once tested at `54.43 MB/s`, but later forced 20MB retests showed much lower and unstable throughput.

## Production Result

Cloudflare DNS records after the final stability retest:

```text
auto.greentraceifm.top   -> 162.159.237.177
auto1.greentraceifm.top  -> 104.17.134.190
auto2.greentraceifm.top  -> 104.17.131.81
auto3.greentraceifm.top  -> 104.17.128.154
auto4.greentraceifm.top  -> 104.17.156.195
```

Final stability table:

```text
ip               latency  cfst_MB/s  min_MB/s  avg_MB/s  ok_rounds
162.159.237.177  154.43   6.72       9.79      9.79      2
104.17.134.190   166.36   6.84       8.51      8.98      2
104.17.131.81    163.84   7.18       8.30      8.41      2
104.17.128.154   144.90   6.88       8.18      9.04      2
104.17.156.195   152.15   6.93       7.88      8.37      2
```

## Deployed Config

Routine daily cron profile:

```text
CFST_DOWNLOAD_COUNT=100
CFST_DOWNLOAD_COUNT_STEP=0
CFST_DOWNLOAD_COUNT_MAX=100
CFST_RESULT_COUNT=5
CFST_PREFER_MIN_SPEED=10
CFST_URL=https://greentrace-speedtest.pages.dev/20mb.bin
CFST_STABILITY_TEST_COUNT=12
CFST_STABILITY_TEST_ROUNDS=2
VALIDATE_CURRENT_ROUNDS=2
CFST_TOTAL_TIMEOUT=4200
CFST_DOWNLOAD_TIMEOUT=30
CFST_MAX_LATENCY=220
PROXY_PLUGIN=1
DRY_RUN=0
```

Manual adaptive sweep profile, only for maintenance windows:

```text
CFST_DOWNLOAD_COUNT=100
CFST_DOWNLOAD_COUNT_STEP=50
CFST_DOWNLOAD_COUNT_MAX=200
```

## Expert Council Decision

Consensus:

- SRE: keep routine downtime bounded. The 2026-05-30 adaptive run expanded to 200 candidates and held PassWall stopped from `08:13:34` to `09:25:22`, but still selected the 100-candidate run as the best source.
- Engineering: use real multi-round downloads as the final ranking signal. This directly targets video stability better than single-run peak throughput.
- Security: no secrets should be stored in GitHub, Notion, or memory. Cloudflare token remains only in OpenWrt `config.env`.

Decision:

- Daily cron uses 100 candidates plus stability retest.
- 150/200 candidate expansion is retained as a manual maintenance-window profile, not a routine daily default.

## Validation

- Local `bash -n cf-dns-speedup.sh`: passed.
- Remote OpenWrt `bash -n`: passed before deployment.
- Full production run: success.
- `stability-update` command: success, reused existing `result.csv` and updated DNS without re-running the long coarse sweep.
- Cloudflare API authoritative records match the final five IPs.
- SmartDNS, dnsmasq, and firewall were running after completion.

## Rollback

Router backups:

```text
/root/openwrt-backup/cf-dns-speedup-stability-2026-05-30-081305
/root/openwrt-backup/cf-dns-speedup-stability-sortfix-2026-05-30-093907
/root/openwrt-backup/cf-dns-speedup-routine-cap-2026-05-30-094400
```

To rollback script/config on OpenWrt, restore from the relevant backup directory and rerun the script in a maintenance window.

## Read-Only Operations

The script also supports read-only operational checks:

```sh
cd /root/cf-dns-speedup
bash ./cf-dns-speedup.sh health-check
bash ./cf-dns-speedup.sh validate-current
```

- `health-check` writes `/root/cf-dns-speedup/health-check.latest.txt` and checks config, selected IPs, DNS, cron, lock, and service state.
- `validate-current` writes `/root/cf-dns-speedup/validate-current.latest.tsv` and retests the currently selected five IPs with real 20MB downloads.
- Neither command updates Cloudflare DNS. `validate-current` also does not stop or restart PassWall.
