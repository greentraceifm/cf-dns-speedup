# OpenWrt CFIP Guard Follow-Up

Date: 2026-06-11

## Context

After the primary-slot quorum and degrade guard deployment on 2026-06-10, the 2026-06-11 06:30 automatic run provided the first real production test.

The run did not select unstable burst IPs into the primary slots, which confirmed the main direction was correct. It exposed two follow-up issues:

- The result list was truncated to only two safe candidates, so `auto2/auto3/auto4` were skipped instead of producing a full candidate list and then blocking the unsafe update.
- `champion-report` still used the older 8 MB/s lifecycle threshold, while `primary-slot-guard` used the newer fallback/quorum rule. This made health-check report primary slots as `ok` while champion-report showed `promotion_ready=0`.

## Expert Review

Conclusion: continue with small, low-risk guard hardening only.

Approved changes:

- Preserve full selector output even when fewer than three candidates satisfy primary-slot quorum.
- Mark missing primary slots explicitly as `missing`.
- Make `assert_primary_slot_guard` block DNS update when any primary slot is `missing`.
- Align champion lifecycle classification with the primary fallback/quorum logic so reports are not misleading.

Rejected for this step:

- No candidate range increase.
- No test file change.
- No cron topology change.
- No PassWall restart outside normal cron.
- No Cloudflare DNS mutation during this deployment.

## Fix 1: Missing Primary Slot Handling

Changed:

- `cf-dns-speedup.sh`
- `tests/run-regression-tests.sh`

Behavior after fix:

```text
selector preserves full candidate count
primary-slot-guard reports missing primary slots
assert_primary_slot_guard blocks DNS update when a primary slot is missing
```

Production evidence from the 2026-06-11 morning run:

```text
selected:
104.17.134.190 min 7.71
104.17.130.225 min 7.29

primary-slot-guard:
1 104.17.134.190 7.71 observations=17 recent_passes=2 ok
2 104.17.130.225 7.29 observations=7  recent_passes=2 ok
3 missing        0.00 observations=0  recent_passes=0 missing
```

Current DNS was preserved:

```text
auto  -> 104.17.134.190
auto1 -> 104.17.130.225
auto2 -> 104.17.136.166
auto3 -> 172.67.69.144
auto4 -> 172.67.79.54
```

Post-fix validation:

```text
104.17.134.190 -> min 7.90 MB/s
104.17.130.225 -> min 7.93 MB/s
104.17.136.166 -> min 9.15 MB/s
172.67.69.144  -> min 5.72 MB/s
172.67.79.54   -> min 6.52 MB/s
```

## Fix 2: Champion Pool Quorum Alignment

Changed:

- `lib/champion-pool.sh`
- `tests/fixtures/dual-pool-observation-history.tsv`
- `tests/fixtures/dual-pool-stability-results.tsv`
- `tests/run-regression-tests.sh`

Behavior after fix:

- Champion lifecycle now uses fallback/quorum logic rather than treating all sub-8 MB/s observations as stale.
- 7.x MB/s candidates that recently pass the primary quorum can be reported as stable/promotion_ready.
- This aligns champion-report with health-check and avoids misleading `promotion_ready=0` when the active primary slots are acceptable.

## Verification

Router regression tests passed after both deployments:

```text
ok - dual-pool keeps stale IP out of primary slots
ok - primary-slot guard reports degraded primary slots
ok - primary-slot guard blocks unsafe DNS update
ok - primary-slot guard blocks missing primary slots
ok - champion lifecycle fields are generated consistently
all regression tests passed
```

No Cloudflare DNS update was performed during these follow-up deployments. PassWall was not restarted manually.

Backups:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260611-guard-missing-slot-fix
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260611-guard-missing-slot-fix
/root/cf-dns-speedup/lib/champion-pool.sh.backup-20260611-champion-quorum-align
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260611-champion-quorum-align
/root/cf-dns-speedup/tests/fixtures/dual-pool-observation-history.tsv.backup-20260611-champion-quorum-align
/root/cf-dns-speedup/tests/fixtures/dual-pool-stability-results.tsv.backup-20260611-champion-quorum-align
```

## GitHub

Commits:

```text
7f723cd Handle missing primary guard slots
```

Champion-pool quorum alignment commit is pending at record creation time.

## Next Recommendation

Let the 14:30 and 20:30 observe-current jobs run. The next review should check:

- `primary-slot-guard` has three `ok` slots, or correctly blocks if missing.
- `champion-report` no longer contradicts health-check for recent 7.x-but-passing primary candidates.
- `promotion_ready` starts recovering toward 2-3.

