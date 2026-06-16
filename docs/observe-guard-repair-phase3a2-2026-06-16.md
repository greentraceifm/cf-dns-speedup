# OpenWrt CFIP Observe Guard Repair Phase 3A-2

Date: 2026-06-16

## Summary

Implemented Phase 3A-2: `observe-current` now automatically appends a `guard-repair` dry-run report after each observation.

This closes the detection loop:

```text
observe-current
  -> validate current DNS
  -> refresh exposed-slot guard state
  -> append observation-history
  -> report DNS repair plan as dry-run
```

It still does not automatically update Cloudflare DNS.

## Evidence

The 2026-06-16 morning run selected:

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
auto3 -> 104.26.7.78
auto4 -> 104.26.5.203
```

Midday validation showed the exposed competitive slots had degraded:

```text
104.17.130.225 -> min 8.53 MB/s
104.17.136.166 -> min 7.14 MB/s
104.17.156.195 -> min 7.81 MB/s
104.26.7.78    -> min 0.54 MB/s
104.26.5.203   -> min 0.24 MB/s
```

The new `observe-current` dry-run report correctly detected the needed DNS-only repair:

```text
auto.greentraceifm.top  104.17.130.225  104.17.130.225 ok
auto1.greentraceifm.top 104.17.136.166  104.17.136.166 ok
auto2.greentraceifm.top 104.17.156.195  104.17.156.195 ok
auto3.greentraceifm.top 104.26.7.78     104.17.130.225 update
auto4.greentraceifm.top 104.26.5.203    104.17.136.166 update
```

## Expert Review

Approved with constraints:

- Dry-run report only after `observe-current`.
- No automatic DNS apply.
- No PassWall restart.
- No cron schedule change.
- No token, firewall, package, topology, speed-test range, or speed-test file changes.

## Implemented Change

Added config:

```text
CFST_OBSERVE_GUARD_REPAIR_REPORT=1
```

Changed:

- `observe_current_command()` now runs `guard_repair_plan_rows` and writes `guard-repair.latest.tsv`.
- Regression coverage asserts that the `guard-repair-dry-run` block remains present.

## Verification

Router regression tests passed:

```text
ok - dual-pool keeps stale IP out of primary slots
ok - exposed slot guard mirrors degraded competitive slots
ok - primary-slot guard reports degraded primary slots
ok - primary-slot guard blocks unsafe DNS update
ok - primary-slot guard blocks missing primary slots
ok - champion lifecycle fields are generated consistently
all regression tests passed
```

Production `observe-current` completed and produced the expected dry-run repair plan. No Cloudflare DNS mutation was performed.

## Backups

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260616-observe-guard-repair-dryrun
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260616-observe-guard-repair-dryrun
```

## Current Action Needed

As of this report, `auto3/auto4` still point to degraded competitive IPs because Phase 3A-2 intentionally reports but does not apply DNS repair.

Recommended manual repair if the user wants immediate 4K stability:

```text
CFST_GUARD_REPAIR_APPLY=1 ./cf-dns-speedup.sh guard-repair
```

This should be treated as a separate DNS-only action.
