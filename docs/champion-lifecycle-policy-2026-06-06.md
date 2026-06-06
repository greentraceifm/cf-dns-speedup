# Champion Lifecycle Policy

Date: 2026-06-06

## Goal

Make champion-pool promotion, demotion, and eviction explainable. The selector already uses the dual-pool strategy; this policy adds lifecycle audit fields so each IP shows why it is stable, watch, challenger, stale, or evicted.

## Lifecycle States

- `challenger`: the IP is fast in the current run but has no observation history yet.
- `watch`: the IP has observation history but has not met stable criteria.
- `stable`: the IP has recent successful observations, recent minimum speed is above the stable slot threshold, and historical low-speed count is within limit.
- `stale`: the IP has repeated low-speed or failed observations.
- `evicted`: the IP reached the failure eviction threshold and is no longer written back to `champion-pool.tsv`.

## Promotion Logic

New IPs start as `challenger` and may only compete for trial slots. They become stable candidates after repeated observation passes:

- recent observation minimum speed is at least `CFST_STABLE_SLOT_MIN_SPEED`
- recent observation succeeded
- low-speed observation count is within `CFST_OBSERVATION_STABLE_MAX_LOW_COUNT`
- consecutive observation passes satisfy the recent observation window

`promotion_ready=1` means the IP is stable enough to be considered for the primary slots.

## Demotion And Eviction

An IP is demoted when recent observations are low-speed or failed. It is marked `stale` when either:

- total low-speed observations reach `CFST_OBSERVATION_STALE_LOW_COUNT`
- the recent observation window is all low-speed or failed

`fail_count` increases when the IP is stale, below the degrade threshold, below the champion fail threshold, or lacks required test rounds. Once `fail_count >= CFST_FAIL_EVICT_COUNT`, the IP is skipped during champion-pool writeback and an `evicted` row is appended to `champion-lifecycle-audit.tsv`.

## Added Champion Pool Columns

The existing `champion-pool.tsv` columns are preserved and these fields are appended:

```text
lifecycle_state
lifecycle_reason
observation_count
consecutive_passes
consecutive_lows
promotion_ready
```

## Audit File

`champion-lifecycle-audit.tsv` records evictions:

```text
observed_at
ip
action
health_status
fail_count
stable_score
lifecycle_reason
```

The audit file does not store secrets or DNS credentials.
