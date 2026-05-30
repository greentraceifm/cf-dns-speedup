# Observability Health Check - 2026-05-31

## Expert Council Decision

The 2026-05-31 night review found the production deployment healthy. The approved change was intentionally narrow:

- Add read-only operational checks.
- Improve run summary evidence.
- Clear stale stability results before a new coarse speed-test run.
- Do not change Cloudflare credentials, firewall, packages, cron schedule, or DNS selection thresholds.

## Implemented

New files written by the script:

```text
/root/cf-dns-speedup/health-check.latest.txt
/root/cf-dns-speedup/validate-current.latest.tsv
```

New commands:

```sh
cd /root/cf-dns-speedup
bash ./cf-dns-speedup.sh health-check
bash ./cf-dns-speedup.sh validate-current
```

Behavior:

- `health-check` is read-only. It reports config, selected IPs, stability results, summary, lock, cron, router DNS, Cloudflare DNS API records, and service health.
- `validate-current` is read-only. It retests the currently selected IPs with `curl --resolve` and `CFST_URL`.
- `validate-current` does not update Cloudflare DNS and does not stop or restart PassWall.
- A new full `run` clears stale `result.stability.tsv` before running CloudflareSpeedTest, so failed or interrupted runs cannot accidentally present old stability rankings as current.

## Deployment Evidence

Router backup before deployment:

```text
/root/openwrt-backup/cf-dns-speedup-observability-2026-05-31-033906
```

Validation:

```text
local bash -n cf-dns-speedup.sh: passed
remote bash -n cf-dns-speedup.sh: passed
health-check: passed
validate-current: passed
```

`health-check` confirmed:

```text
CFST_DOWNLOAD_COUNT=100
CFST_DOWNLOAD_COUNT_STEP=0
CFST_DOWNLOAD_COUNT_MAX=100
CFST_STABILITY_TEST_COUNT=12
CFST_STABILITY_TEST_ROUNDS=2
cron: 06:30 daily active; 15:30 adaptive run disabled
lock: no_lock
SmartDNS: running
dnsmasq: running
firewall: active with no instances
```

DNS consistency:

```text
auto.greentraceifm.top   router/cloudflare -> 162.159.237.177
auto1.greentraceifm.top  router/cloudflare -> 104.17.134.190
auto2.greentraceifm.top  router/cloudflare -> 104.17.131.81
auto3.greentraceifm.top  router/cloudflare -> 104.17.128.154
auto4.greentraceifm.top  router/cloudflare -> 104.17.156.195
```

`validate-current` result:

```text
ip               previous_min  measured_min  measured_avg  ok_rounds
162.159.237.177  9.79          8.02          8.98          2
104.17.134.190   8.51          7.92          8.18          2
104.17.131.81    8.30          7.82          8.41          2
104.17.128.154   8.18          8.15          8.23          2
104.17.156.195   7.88          9.33          9.47          2
```

## Remaining Note

`last-run.summary` may still show the last DNS-writing run until the next scheduled `run`. This is expected; `health-check` shows both current config and last-run evidence so the difference is visible.
