# OpenWrt CFIP Stable Pool Recovery

Date: 2026-06-12

## Summary

The 2026-06-12 morning run showed that the primary-slot quorum guard and champion-pool quorum alignment are working.

The system recovered from the previous `missing` primary-slot state to three safe primary slots.

## Current Primary Slots

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
auto3 -> 104.26.13.109
auto4 -> 104.26.3.215
```

## Health Evidence

`primary-slot-guard`:

```text
1 104.17.130.225 9.27 observations=9  recent_passes=2 ok
2 104.17.136.166 7.83 observations=12 recent_passes=2 ok
3 104.17.156.195 6.84 observations=9  recent_passes=2 ok
```

`champion-summary`:

```text
total=10
stable=3
watch=4
stale=3
promotion_ready=3
with_fail_count=3
stable_pool=7
competitive_pool=3
```

Post-run `validate-current`:

```text
104.17.130.225 -> min 7.77 MB/s, avg 8.30 MB/s
104.17.136.166 -> min 9.27 MB/s, avg 9.45 MB/s
104.17.156.195 -> min 6.88 MB/s, avg 7.49 MB/s
104.26.13.109  -> min 6.79 MB/s, avg 6.83 MB/s
104.26.3.215   -> min 7.48 MB/s, avg 7.98 MB/s
```

## Expert Review

Decision: do not add historical stable-candidate backfill today.

Reason:

- The stable pool recovered naturally.
- `promotion_ready=3`, meeting the target.
- All three primary slots are in 104.17.* and pass quorum.
- 104.26.* candidates remained in competitive slots despite high morning speed, which is the intended behavior.

Approved low-risk improvement:

- Add `champion-summary` to `health-check`.
- This is read-only reporting and does not alter selection, DNS, cron, PassWall, tokens, or firewall.

## Deployed Change

Changed:

- `cf-dns-speedup.sh`
- `tests/run-regression-tests.sh`

Added health-check section:

```text
=== champion-summary ===
total=10
stable=3
watch=4
stale=3
promotion_ready=3
with_fail_count=3
stable_pool=7
competitive_pool=3
```

## Verification

Router regression tests passed:

```text
ok - dual-pool keeps stale IP out of primary slots
ok - primary-slot guard reports degraded primary slots
ok - primary-slot guard blocks unsafe DNS update
ok - primary-slot guard blocks missing primary slots
ok - champion lifecycle fields are generated consistently
all regression tests passed
```

No Cloudflare DNS update was performed by this deployment. PassWall was not manually restarted.

Backups:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260612-health-champion-summary
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260612-health-champion-summary
```

## Next Recommendation

Let the 14:30 and 20:30 observation jobs run. If primary slots remain `ok` and `promotion_ready` stays at least 3, the next worthwhile phase is documentation/report polish or Phase 2B observation modularization. Avoid new selection changes until another real instability appears.

