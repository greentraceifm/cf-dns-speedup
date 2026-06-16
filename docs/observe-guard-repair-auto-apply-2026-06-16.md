# OpenWrt CFIP Observe Guard Repair Auto Apply - 2026-06-16

## Summary

Phase 3A-3 adds a conservative auto-repair gate to `observe-current`.

The goal is to prevent degraded exposed competitive slots, usually `auto3` and `auto4`, from staying live until manual intervention. The primary slots remain protected by the stable pool, primary quorum, and degradation guard.

## Expert Council Decision

The approved approach was narrow and operationally conservative:

- Keep `auto/auto1/auto2` governed by the stable pool.
- Let `observe-current` continue to validate the currently exposed DNS slots.
- After observation, generate the normal `guard-repair` dry-run report.
- If explicitly enabled, auto-apply only the already planned `guard-repair` updates.
- Limit the number of automatic DNS updates, defaulting to 2.
- Do not restart PassWall.
- Do not change cron, firewall, token, package, topology, or speed-test parameters.

## Implementation

New configuration:

```sh
CFST_OBSERVE_GUARD_REPAIR_REPORT=1
CFST_OBSERVE_GUARD_REPAIR_APPLY=1
CFST_OBSERVE_GUARD_REPAIR_MAX_UPDATES=2
```

New helper behavior:

- `guard_repair_update_count` counts pending `update/create` actions in `guard-repair.latest.tsv`.
- `apply_guard_repair_report_updates` applies only those planned rows.
- `observe-current` prints a `guard-repair-auto-apply` section when the apply switch is enabled.

Blocked cases:

- No updates: `status=skipped_no_updates`.
- Too many updates: `status=blocked_too_many_updates`.
- Missing report: fail closed.

## Deployment

Deployed on router:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh
/root/cf-dns-speedup/tests/run-regression-tests.sh
/root/cf-dns-speedup/config.env
```

Backups were saved under:

```text
/root/cf-dns-speedup/backups/
```

No PassWall restart was performed.

## Verification

Local Git Bash:

```text
all regression tests passed
```

OpenWrt staging directory:

```text
sh -n ./cf-dns-speedup.sh
sh -n ./tests/run-regression-tests.sh
all regression tests passed
```

OpenWrt production directory:

```text
all regression tests passed
```

Production `observe-current` after deployment:

```text
104.17.130.225 -> min 9.09 MB/s
104.17.136.166 -> min 7.13 MB/s
104.17.156.195 -> min 7.26 MB/s
104.17.130.225 -> min 8.92 MB/s
104.17.136.166 -> min 7.03 MB/s
```

Auto-apply gate output:

```text
updates=0
max_updates=2
status=skipped_no_updates
```

DNS and Cloudflare API were consistent for `auto` through `auto4` after observation:

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
auto3 -> 104.17.130.225
auto4 -> 104.17.136.166
```

PassWall remained running.

## Expected Effect

If `auto3` or `auto4` later degrades below the exposed-slot threshold during scheduled observation, `observe-current` can now automatically replace it with the stable primary mirror selected by `selected_dns_rows`.

This does not make Cloudflare IP quality permanent, but it removes the main operational gap found on 2026-06-16: degraded competitive slots were detected but remained exposed until manual repair.
