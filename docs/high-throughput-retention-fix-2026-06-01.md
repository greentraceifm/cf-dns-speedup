# High-throughput retention fix, 2026-06-01

## Problem

The 2026-06-01 morning run selected several new Cloudflare IPs that were fast during the 06:30 stability retest but degraded later in the day. A read-only 20 MB retest showed multiple selected IPs around 2 MB/s while older stable and champion-pool IPs still measured around 8-9 MB/s.

## Changes

- Added `CFST_RETAIN_MIN_SPEED`, default `8`, so current DNS and champion candidates only receive retention boost when their current stability-retest minimum speed is high enough.
- Required full successful stability rounds before retention boost is applied.
- Penalized candidates below `CFST_DEGRADE_MIN_SPEED` during stability sorting.
- Changed champion-pool ranking to prefer recent measured speed first, then historical best speed.
- Fixed stability and validate-current download probes so a curl timeout records a failed round instead of aborting the whole command.
- Added `stability-verify`, a read-only command that reuses the existing `result.csv`, runs the stability retest, and prints the would-be selected IPs without stopping the proxy, updating DNS, or sending notifications.
- Tightened external observation promotion by requiring all configured promotion rounds to pass and raised the example promotion speed threshold to 8 MB/s.

## Deployment defaults

Recommended production values:

```sh
CFST_RETAIN_MIN_SPEED=8
CFST_DEGRADE_MIN_SPEED=2
CFST_EXTERNAL_PROMOTION_MIN_SPEED=8
```

`stability-verify` should be used before a maintenance-window `stability-update` when diagnosing daytime or evening throughput degradation.

## 2026-06-01 deployment result

OpenWrt deployment path: `/root/cf-dns-speedup`.

Post-fix selected DNS records:

```text
auto.greentraceifm.top  -> 104.17.134.190
auto1.greentraceifm.top -> 104.17.158.242
auto2.greentraceifm.top -> 104.17.156.195
auto3.greentraceifm.top -> 104.17.151.5
auto4.greentraceifm.top -> 104.17.128.154
```

Post-update `validate-current` result:

```text
104.17.134.190  min 9.46 MB/s  avg 9.54 MB/s
104.17.158.242  min 9.59 MB/s  avg 9.81 MB/s
104.17.156.195  min 8.06 MB/s  avg 8.21 MB/s
104.17.151.5    min 8.61 MB/s  avg 9.20 MB/s
104.17.128.154  min 7.31 MB/s  avg 7.87 MB/s
```

Final health check confirmed router DNS and Cloudflare API records matched for all five records after TTL expiry.
