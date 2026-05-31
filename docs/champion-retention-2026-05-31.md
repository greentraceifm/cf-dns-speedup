# OpenWrt Cloudflare IP champion retention

Date: 2026-05-31

## Problem

The 2026-05-31 morning scan selected five IPs that passed the short stability retest at about 10 MB/s, but they dropped to below 1 MB/s later in the day. The previously selected 2026-05-30 IP group still tested around 7-10 MB/s at the same time.

The failure mode was not caused by `health-check`. The daily update replaced a known-good group with short-lived morning winners because the script only ranked the latest scan result.

## Change

The stability retest now builds the final candidate set from three sources:

- `new`: candidates from the latest CloudflareSpeedTest scan.
- `current_dns`: IPs currently published in Cloudflare DNS.
- `champion`: historical high-throughput IPs saved in `champion-pool.tsv`.

All candidates are retested with the same `CFST_URL`, then sorted by a retention-aware score. Current DNS IPs are kept unless they are degraded or a new IP is clearly better. The champion pool is updated after each retest and keeps up to the configured number of best historical IPs.

## New settings

```sh
CFST_COMPARE_CURRENT_DNS=1
CFST_CHAMPION_POOL=1
CFST_CHAMPION_POOL_SIZE=10
CFST_RETAIN_RATIO=0.90
CFST_REPLACE_IMPROVE_RATIO=1.25
CFST_DEGRADE_MIN_SPEED=2
CFST_FAIL_EVICT_COUNT=3
CFST_FINAL_CANDIDATE_LIMIT=20
```

## Operational notes

- `champion-pool.tsv` is runtime state and should not contain secrets.
- A current DNS IP below `CFST_DEGRADE_MIN_SPEED` is treated as degraded and can be replaced.
- A champion IP is evicted only after `CFST_FAIL_EVICT_COUNT` degraded retests.
- `stability-update` still stops and restarts the configured proxy plugin because it may update DNS. Use `validate-current` for read-only observation.

