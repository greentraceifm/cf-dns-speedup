# OpenWrt CFIP Exposed Slot Guard

Date: 2026-06-14

## Summary

The primary `auto/auto1/auto2` slots remained healthy, but the competitive `auto3/auto4` slots degraded sharply after the morning run.

Read-only validation showed:

```text
104.17.130.225 -> min 7.80 MB/s
104.17.136.166 -> min 7.33 MB/s
104.17.156.195 -> min 7.62 MB/s
104.20.29.46  -> min 0.54 MB/s
104.26.7.78   -> min 0.25 MB/s
```

This confirmed that the remaining instability was not the primary-slot quorum logic. The risk was exposing degraded competitive slots through DNS.

## Expert Review

Decision: add a guarded DNS-output layer for exposed slots.

Approved behavior:

- Keep `selected` candidates unchanged for reporting and champion-pool learning.
- Keep `auto/auto1/auto2` controlled by the primary quorum guard.
- For `auto3/auto4`, if the latest validation speed is below `CFST_EXPOSED_SLOT_MIN_SPEED` (default `6.5 MB/s`), mirror those DNS outputs back to stable primary slots.
- Do not change speed-test range, download file, cron, token, firewall, package versions, or PassWall behavior.

## Implemented Change

Added:

- `selected_dns_rows()`
- `print_exposed_slot_guard()`
- `dns-selected` section in `health-check`
- `exposed-slot-guard` section in `health-check`
- Regression coverage for degraded competitive slots being mirrored to stable slots.

The production script was deployed with backups:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260614-exposed-slot-guard
/root/cf-dns-speedup/tests/run-regression-tests.sh.backup-20260614-exposed-slot-guard
```

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

Post-deployment health-check:

```text
=== dns-selected ===
104.17.130.225
104.17.136.166
104.17.156.195
104.17.130.225
104.17.136.166

=== exposed-slot-guard ===
slot selected_ip      dns_ip          effective_min_mbps status
1    104.17.130.225  104.17.130.225  7.80               primary
2    104.17.136.166  104.17.136.166  7.33               primary
3    104.17.156.195  104.17.156.195  7.62               primary
4    104.20.29.46    104.17.130.225  0.54               mirrored
5    104.26.7.78     104.17.136.166  0.25               mirrored
```

## Operational Note

No Cloudflare DNS mutation was performed during deployment. The guard will affect the next normal DNS update. A manual DNS update can be run separately if immediate correction of `auto3/auto4` is desired.
