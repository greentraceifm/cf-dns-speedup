# OpenWrt CFIP Primary Quorum and Degrade Guard

Date: 2026-06-10

## Purpose

This deployment adds a stricter primary-slot safety layer for the OpenWrt Cloudflare preferred-IP project.

The previous primary-slot guard stopped unobserved burst-speed challengers from directly taking `auto/auto1/auto2`. This update closes the remaining gap: if a candidate does not have enough recent successful observations, or if a primary slot is degraded, the script should keep the existing DNS instead of writing unsafe new records.

## Expert Council Review

Decision: approved.

Recommended shape:

- Add a quorum rule for the primary slots only.
- Add a DNS-update block when primary slots are unsafe.
- Keep exploration in `auto3/auto4`.
- Do not change test file, candidate range, cron topology, Cloudflare token, firewall, packages, or PassWall topology.
- Keep the feature configurable and observable through `health-check`.

## New Rules

Primary slots are `auto`, `auto1`, and `auto2`.

Default quorum:

```sh
CFST_PRIMARY_QUORUM_MODE=1
CFST_PRIMARY_QUORUM_MIN_OBSERVATIONS=2
CFST_PRIMARY_QUORUM_RECENT_PASSES=2
```

Meaning:

- A candidate needs at least two observation records before it can be trusted for a primary slot.
- The recent observation window must contain two passing observations.
- Single-run high speed is no longer enough for `auto/auto1/auto2`.

Default degrade guard:

```sh
CFST_PRIMARY_DEGRADE_PROTECTION=1
CFST_PRIMARY_DEGRADE_MIN_SPEED=2
CFST_PRIMARY_GUARD_ENFORCE=1
```

Meaning:

- A primary slot candidate below the degrade threshold is unsafe.
- If any primary slot is `degraded`, `below_primary_floor`, or `quorum_pending`, DNS update is blocked.
- The current DNS is preserved instead of writing unstable candidates.

## Code Changes

Changed:

- `cf-dns-speedup.sh`
- `config.example.env`
- `tests/run-regression-tests.sh`
- `tests/fixtures/dual-pool-observation-history.tsv`
- `tests/fixtures/dual-pool-stability-results.tsv`

Main additions:

- `quorum_pass()` checks in:
  - `apply_dual_pool_slots`
  - `promote_primary_safe_candidate`
  - `promote_stable_slots`
- `print_primary_slot_guard()` in `health-check`
- `assert_primary_slot_guard()` before Cloudflare DNS update
- `primary-slot-guard.blocked.tsv` evidence file when DNS update is blocked

## Router Deployment

Router: `192.168.1.254`

Project path:

```text
/root/cf-dns-speedup
```

Backups:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260610-quorum-guard
/root/cf-dns-speedup/config.env.backup-20260610-quorum-guard
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260610-quorum-guard
/root/cf-dns-speedup/tests/fixtures/dual-pool-observation-history.tsv.backup-20260610-quorum-guard
/root/cf-dns-speedup/tests/fixtures/dual-pool-stability-results.tsv.backup-20260610-quorum-guard
```

Router `config.env` now includes:

```sh
CFST_PRIMARY_QUORUM_MODE=1
CFST_PRIMARY_QUORUM_MIN_OBSERVATIONS=2
CFST_PRIMARY_QUORUM_RECENT_PASSES=2
CFST_PRIMARY_DEGRADE_PROTECTION=1
CFST_PRIMARY_DEGRADE_MIN_SPEED=2
CFST_PRIMARY_GUARD_ENFORCE=1
```

## Verification

No Cloudflare DNS update was performed during this deployment. PassWall was not restarted.

Regression tests passed on the router:

```text
ok - dual-pool keeps stale IP out of primary slots
ok - primary-slot guard reports degraded primary slots
ok - primary-slot guard blocks unsafe DNS update
ok - champion lifecycle fields are generated consistently
all regression tests passed
```

`health-check` after deployment shows the guard is active:

```text
CFST_PRIMARY_QUORUM_MODE=1
CFST_PRIMARY_QUORUM_MIN_OBSERVATIONS=2
CFST_PRIMARY_QUORUM_RECENT_PASSES=2
CFST_PRIMARY_DEGRADE_PROTECTION=1
CFST_PRIMARY_DEGRADE_MIN_SPEED=2.00
CFST_PRIMARY_GUARD_ENFORCE=1
```

Primary slot guard status:

```text
slot  ip              min_speed_mbps  observations  recent_passes  status
1     104.17.134.190  8.76            16            2              ok
2     104.17.130.225  8.71            6             2              ok
3     104.17.136.166  8.09            9             2              ok
```

Post-deployment `validate-current`:

```text
104.17.134.190 -> min 8.64 MB/s, avg 8.69 MB/s
104.17.130.225 -> min 8.77 MB/s, avg 8.98 MB/s
104.17.136.166 -> min 9.31 MB/s, avg 9.36 MB/s
172.67.69.144  -> min 0.49 MB/s, avg 1.31 MB/s
172.67.79.54   -> min 0.44 MB/s, avg 1.36 MB/s
```

## Result

The project now follows a conservative rule:

```text
No quorum, no primary slot.
Unsafe primary slot, no DNS update.
```

This should materially reduce future cases where a short-lived high-speed IP breaks `auto` playback.

## Remaining Caveat

This does not guarantee Cloudflare anycast IPs will never degrade. It prevents bad candidates from taking over the main route and preserves the last known DNS when the new result is unsafe.

The next observation windows should be used to grow the stable pool depth from `promotion_ready=1` toward at least `2-3`.

