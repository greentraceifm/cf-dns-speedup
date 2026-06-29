# OpenWrt CFIP Phase 4 Fast Rescue Scan - 2026-06-29

## Summary

Phase 4 adds a fast live rescue scan behind the existing emergency refresh guard. The goal is to reduce recovery time when all protected primary slots degrade, without lowering DNS safety standards.

The previous emergency refresh could only retest candidates already present in `result.stability.tsv`. If those candidates were stale or from a different time-of-day window, the system would correctly refuse to update but had no fast way to find fresh replacements. Phase 4 adds a bounded live scan fallback.

## Expert Review

Approved with these boundaries:

- Use fresh current-time validation before any DNS update.
- Keep the primary quorum and degrade guard intact.
- Do not lower the replacement threshold below `CFST_EMERGENCY_REFRESH_MIN_SPEED`.
- Do not stop or restart PassWall for the rescue scan.
- Do not overwrite production `result.csv` or `result.stability.tsv` during rescue scanning.
- If no fresh candidate passes, keep existing DNS and report `no_safe_replacement`.

## Implemented

New report file:

```text
/root/cf-dns-speedup/emergency-rescue-scan.latest.tsv
```

New config:

```text
CFST_EMERGENCY_RESCUE_SCAN=1
CFST_EMERGENCY_RESCUE_DOWNLOAD_COUNT=40
CFST_EMERGENCY_RESCUE_TOTAL_TIMEOUT=1500
CFST_EMERGENCY_RESCUE_STABILITY_COUNT=8
CFST_EMERGENCY_RESCUE_STABILITY_ROUNDS=2
```

New behavior:

1. `emergency-refresh` first validates current DNS.
2. If primary slots are not all degraded, it exits with `status=skipped_primary_not_degraded`.
3. If they are degraded, it retests existing emergency candidates.
4. If too few pass, it runs a bounded live rescue scan using temporary result files.
5. The rescue result is copied to `emergency-rescue-scan.latest.tsv` and reused by the same emergency DNS planning logic.
6. If fresh passing candidates are still insufficient, it reports `status=no_safe_replacement` and makes no DNS change.

## Deployment

Router path: `/root/cf-dns-speedup`.

Backup stamp:

```text
20260629-091244-phase4-rescue-scan
```

Backups include script, tests, and config under `/root/openwrt-backup`.

No PassWall restart, firewall change, token change, package change, or cron topology change was performed.

## Validation

Local and OpenWrt checks passed:

```text
bash -n cf-dns-speedup.sh
sh tests/run-regression-tests.sh
all regression tests passed
```

Production health check showed Phase 4 config active:

```text
CFST_EMERGENCY_RESCUE_SCAN=1
CFST_EMERGENCY_RESCUE_DOWNLOAD_COUNT=40
CFST_EMERGENCY_RESCUE_TOTAL_TIMEOUT=1500
CFST_EMERGENCY_RESCUE_STABILITY_COUNT=8
CFST_EMERGENCY_RESCUE_STABILITY_ROUNDS=2
```

Dry-run emergency check after deployment:

```text
104.17.130.225 min 8.36 MB/s avg 8.88 MB/s
104.17.156.195 min 8.51 MB/s avg 9.02 MB/s
104.17.136.166 min 8.24 MB/s avg 8.58 MB/s
104.17.130.225 min 7.85 MB/s avg 8.66 MB/s
104.17.156.195 min 9.04 MB/s avg 9.09 MB/s
status=skipped_primary_not_degraded
```

This is the desired behavior: since current auto slots are healthy, the rescue scan did not run and no DNS update was attempted.

## Operational Meaning

The system now has three layers:

1. Normal morning selection with primary-slot quorum guard.
2. Observe-current guard repair for degraded exposed slots.
3. Emergency refresh with fast live rescue scan only when all primary slots degrade.

This does not guarantee perfect 4K playback during every ISP/Cloudflare peak-hour event, but it prevents unsafe replacements and gives the system a bounded recovery path when fresh better candidates exist.
