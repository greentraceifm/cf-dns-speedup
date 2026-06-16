# OpenWrt CFIP DNS Guard Repair Apply - 2026-06-16

## Summary

On 2026-06-16, the exposed competitive slots degraded after the morning preferred-IP run. The stable primary slots remained acceptable, but `auto3` and `auto4` were still pointing at degraded competitive IPs.

The approved repair was a DNS-only `guard-repair` apply:

- No PassWall restart.
- No cron, firewall, token, package, or topology change.
- No speed-test parameter change.
- Only Cloudflare DNS records for degraded exposed slots were updated.

## Evidence Before Repair

Morning selected DNS:

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
auto3 -> 104.26.7.78
auto4 -> 104.26.5.203
```

Midday observation showed exposed slot degradation:

```text
104.17.130.225 -> min 8.53 MB/s
104.17.136.166 -> min 7.14 MB/s
104.17.156.195 -> min 7.81 MB/s
104.26.7.78    -> min 0.54 MB/s
104.26.5.203   -> min 0.24 MB/s
```

Dry-run repair plan:

```text
auto3.greentraceifm.top 104.26.7.78  -> 104.17.130.225 update
auto4.greentraceifm.top 104.26.5.203 -> 104.17.136.166 update
```

## Expert Council Decision

The council recommendation was to close the loop with the smallest safe mutation:

- Treat the issue as an exposed-slot repair gap, not a broad candidate discovery problem.
- Apply DNS-only repair for degraded exposed competitive slots.
- Keep competitive IPs in observation, but do not let degraded competitive slots remain exposed to users.
- Keep PassWall untouched because the failure was DNS slot selection, not proxy service state.

Action Gate classified Cloudflare DNS mutation as high-risk and requiring human authorization. User authorization had already been given for expert-reviewed implementation.

## Applied Change

Command class:

```sh
CFST_GUARD_REPAIR_APPLY=1 ./cf-dns-speedup.sh guard-repair
```

Applied updates:

```text
auto3.greentraceifm.top: 104.26.7.78  -> 104.17.130.225
auto4.greentraceifm.top: 104.26.5.203 -> 104.17.136.166
```

## Verification

Regression tests:

```text
all regression tests passed
```

Post-apply `guard-repair` after DNS cache refresh:

```text
auto.greentraceifm.top  104.17.130.225 104.17.130.225 ok
auto1.greentraceifm.top 104.17.136.166 104.17.136.166 ok
auto2.greentraceifm.top 104.17.156.195 104.17.156.195 ok
auto3.greentraceifm.top 104.17.130.225 104.17.130.225 ok
auto4.greentraceifm.top 104.17.136.166 104.17.136.166 ok
```

Post-apply validation:

```text
104.17.130.225 -> min 8.60 MB/s
104.17.136.166 -> min 6.85 MB/s
104.17.156.195 -> min 7.88 MB/s
104.17.130.225 -> min 7.64 MB/s
104.17.136.166 -> min 7.31 MB/s
```

PassWall remained running.

## Follow-Up Recommendation

The next optimization should make this repair loop safer and more automatic:

1. Add a conservative auto-apply mode for exposed competitive slots only.
2. Require the replacement target to be a stable primary mirror.
3. Require at least one fresh `validate-current` or `observe-current` showing the exposed slot below threshold.
4. Keep primary slots protected by quorum and degradation guard.
5. Continue reporting all repair decisions to `guard-repair.latest.tsv`.

This would prevent future `auto3/auto4` degradation from persisting until manual intervention, while keeping `auto/auto1/auto2` governed by the stricter stable pool.
