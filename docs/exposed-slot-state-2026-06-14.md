# OpenWrt CFIP Exposed Slot State

Date: 2026-06-14

## Summary

After the DNS-only repair, a persistence gap was found in the exposed-slot guard.

The DNS records were corrected to stable mirrored slots, but `validate-current` then measured only the currently exposed stable DNS records. That meant the low-speed evidence for the old competitive IPs could disappear from the latest validation file.

Without persistent state, a later DNS-only operation could re-expose old high-peak competitive IPs from `result.stability.tsv`.

## Implemented Change

Added persistent exposed-slot guard state:

```text
/root/cf-dns-speedup/exposed-slot-guard.tsv
```

The state records recently degraded competitive IPs for `CFST_EXPOSED_SLOT_BLOCK_TTL_SECONDS`, defaulting to 43200 seconds / 12 hours.

Added config:

```text
CFST_EXPOSED_SLOT_GUARD=1
CFST_EXPOSED_SLOT_MIN_SPEED=6.5
CFST_EXPOSED_SLOT_BLOCK_TTL_SECONDS=43200
EXPOSED_SLOT_GUARD_STATE_FILE=/root/cf-dns-speedup/exposed-slot-guard.tsv
```

Added behavior:

- `validate-current` refreshes exposed-slot guard state.
- `selected_dns_rows()` consults both latest validation and persistent state.
- `print_exposed_slot_guard()` reports state-aware mirrored/exposed decisions.
- State-file reads tolerate CRLF line endings.

Seeded current degraded competitive IPs:

```text
104.20.29.46  0.54 MB/s  blocked
104.26.7.78   0.25 MB/s  blocked
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

Post-deployment `health-check`:

```text
=== dns-selected ===
104.17.130.225
104.17.136.166
104.17.156.195
104.17.130.225
104.17.136.166

=== exposed-slot-guard ===
slot selected_ip      dns_ip          effective_min_mbps status
1    104.17.130.225  104.17.130.225  8.95               primary
2    104.17.136.166  104.17.136.166  8.13               primary
3    104.17.156.195  104.17.156.195  7.01               primary
4    104.20.29.46    104.17.130.225  0.54               mirrored
5    104.26.7.78     104.17.136.166  0.25               mirrored
```

## Operational Impact

No Cloudflare DNS mutation was performed by this deployment. No PassWall restart, cron change, token change, firewall change, package change, or speed-test parameter change was performed.

This change prevents old degraded competitive slots from being re-exposed during later DNS-only operations while still allowing them to recover after the block TTL or after a new successful validation.
