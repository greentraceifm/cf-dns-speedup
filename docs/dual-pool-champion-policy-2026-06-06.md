# Dual Pool Champion Policy

Date: 2026-06-06

## Problem

The previous champion pool could be polluted by morning burst-speed IPs. On 2026-06-06, `104.26.2.86` was selected for `auto.greentraceifm.top` even though observation history already marked it as stale and current validation showed it below `1 MB/s`.

## Policy

The selector now separates stable and competitive behavior:

- Stable candidates are responsible for `auto`, `auto1`, and `auto2`.
- Competitive candidates can fill the remaining slots but should not displace stable candidates in the primary slots.
- Stale candidates are strongly penalized even when a single morning retest is fast.

Default weights:

- Stable score: observation average minimum speed `60%`, current retest minimum speed `30%`, historical best minimum speed `10%`.
- Competitive score: current retest minimum speed `60%`, historical best minimum speed `30%`, observation average minimum speed `10%`.

## New Settings

```sh
CFST_DUAL_POOL_MODE=1
CFST_COMPETITIVE_SLOT_COUNT=2
CFST_OBSERVATION_RECENT_WINDOW=2
CFST_OBSERVATION_STALE_LOW_COUNT=3
CFST_OBSERVATION_STABLE_MAX_LOW_COUNT=1
```

## Champion Pool Compatibility

`champion-pool.tsv` keeps the original columns and appends:

```text
health_status
stable_score
recent_low_count
pool_type
```

Existing champion pool files remain readable.

## Expected Result

The daily DNS update should prefer long-term stable IPs for the primary records and keep newly fast IPs in competitive slots until observation history proves they are stable.

## Rollback

Restore the previous `/root/cf-dns-speedup/cf-dns-speedup.sh` backup and run read-only `health-check` before any DNS update.
