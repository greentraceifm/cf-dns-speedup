# Adaptive Throughput Selection - 2026-05-30

## Expert Council Decision

The high-throughput result on 2026-05-30 showed that the 20MB test can discover unusually fast candidates:

```text
172.67.79.2      78.63 ms   54.43 MB/s
104.20.30.120    80.24 ms   19.47 MB/s
172.67.66.188    76.85 ms   11.30 MB/s
```

Council recommendation:

- Prefer high-throughput IPs, but do not use a hard speed floor that can leave fewer than five DNS records updated.
- If fewer than five IPs meet the preferred speed threshold, increase the download-tested candidate range by 50 and test again.
- Set a maximum candidate range to avoid excessive PassWall downtime.
- If the maximum range still has fewer than five preferred IPs, fill the remaining slots with the next-fastest candidates.

## New Config Knobs

```text
CFST_PREFER_MIN_SPEED=10
CFST_DOWNLOAD_COUNT_STEP=50
CFST_DOWNLOAD_COUNT_MAX=200
```

These are intentionally separate from `CFST_MIN_SPEED`.

- `CFST_MIN_SPEED` is the hard `cfst` speed filter. Keep it at `0` for production safety.
- `CFST_PREFER_MIN_SPEED` is a soft ranking preference. Matching IPs are selected first; non-matching IPs are used only to fill the final result count.

## Production Profile

```text
CFST_DOWNLOAD_COUNT=100
CFST_DOWNLOAD_COUNT_STEP=50
CFST_DOWNLOAD_COUNT_MAX=200
CFST_RESULT_COUNT=5
CFST_PREFER_MIN_SPEED=10
CFST_TOTAL_TIMEOUT=4200
CFST_DOWNLOAD_TIMEOUT=30
CFST_MAX_LATENCY=220
CFST_URL=https://greentrace-speedtest.pages.dev/20mb.bin
```

## Operational Notes

- This can run longer than the previous Stage 2 profile if the first 100 candidates do not produce five IPs above `10 MB/s`.
- PassWall remains stopped during the speed-test phase, so keep the cron schedule outside normal use windows.
- The 15:30 cron entry should be removed or disabled unless an afternoon retest is explicitly wanted.
