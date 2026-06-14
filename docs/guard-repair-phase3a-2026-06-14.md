# OpenWrt CFIP Guard Repair Phase 3A

Date: 2026-06-14

## Summary

Implemented Phase 3A-1: a guarded DNS repair command for the exposed-slot protection workflow.

The command compares `dns-selected` against current Cloudflare DNS records and reports whether each `auto` record is already correct or needs repair.

Default behavior is dry-run only:

```text
CFST_GUARD_REPAIR_APPLY=0
```

Cloudflare DNS is updated only when explicitly run with:

```text
CFST_GUARD_REPAIR_APPLY=1
```

## Expert Review

Approved with constraints:

- Default to dry-run.
- No automatic cron integration yet.
- No PassWall restart.
- No speed-test range or file changes.
- No token, firewall, package, or topology changes.
- Apply mode must remain explicit.

## Implemented Change

Added command:

```text
./cf-dns-speedup.sh guard-repair
```

Added helpers:

- `guard_repair_desired_rows()`
- `guard_repair_current_rows()`
- `guard_repair_plan_rows()`
- `guard_repair_command()`

Added config/reporting:

```text
CFST_GUARD_REPAIR_APPLY=0
GUARD_REPAIR_REPORT_FILE=/root/cf-dns-speedup/guard-repair.latest.tsv
```

Added regression coverage that verifies `guard-repair` plans `auto3/auto4` updates when current DNS still exposes degraded competitive IPs but `dns-selected` has mirrored stable slots.

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

Production dry-run:

```text
name                    current_ip      desired_ip      action
auto.greentraceifm.top  104.17.130.225  104.17.130.225 ok
auto1.greentraceifm.top 104.17.136.166  104.17.136.166 ok
auto2.greentraceifm.top 104.17.156.195  104.17.156.195 ok
auto3.greentraceifm.top 104.17.130.225  104.17.130.225 ok
auto4.greentraceifm.top 104.17.136.166  104.17.136.166 ok
```

No DNS mutation was performed by the production dry-run.

## Backups

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260614-guard-repair-dryrun
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260614-guard-repair-dryrun
```

## Next Step

Observe the next normal `observe-current` and morning auto run. If `guard-repair` reports accurately for 1-2 cycles, the next phase can wire it as a dry-run report after `observe-current`. Automatic apply should remain disabled until more evidence is collected.
