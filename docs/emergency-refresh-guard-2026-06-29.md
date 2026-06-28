# OpenWrt CFIP Emergency Refresh Deployment - 2026-06-29

## Summary

User reported that `auto.greentraceifm.top` could not play 4K YouTube smoothly. The investigation found a time-of-day throughput collapse rather than a Cloudflare DNS mismatch or PassWall outage.

The deployed fix adds two protections:

1. Stable-mirror guard repair: when the last successful/failed candidate result contains unsafe challenger IPs, `guard-repair` preserves current primary slots and only mirrors degraded exposed slots back to stable primary IPs.
2. Emergency refresh: when all primary slots validate below the emergency threshold, the script freshly retests recent high-speed candidates with real `curl --resolve` downloads before allowing a bounded DNS replacement.

## IT Expert Review

Action Gate classified the OpenWrt + Cloudflare DNS work as high risk. User authorization was explicit. Expert consensus:

- Do not blindly write morning high-speed challengers into `auto/auto1/auto2`.
- Preserve primary-slot quorum and degrade guards.
- Add a controlled emergency path for the case where the stable pool itself collapses.
- Use fresh validation at the current time before any emergency promotion.
- Keep PassWall, firewall, package versions, tokens, and cron topology unchanged.

## Evidence

### Current DNS before emergency logic

```text
auto  -> 104.17.130.225
auto1 -> 104.17.156.195
auto2 -> 104.17.136.166
auto3 -> 104.17.130.225
auto4 -> 104.17.156.195
```

### Low-speed incident evidence

At night, `validate-current` showed primary slots around `0.20-1.86 MB/s`, which explains 4K YouTube buffering.

Morning candidates that looked fast in `result.stability.tsv` were retested by emergency refresh and failed real current validation:

```text
104.26.0.246  min 0.03 MB/s
104.26.9.147  min 0.01 MB/s
172.67.70.184 min 0.00 MB/s
104.20.22.118 min 0.07 MB/s
172.67.72.122 min 0.06 MB/s
```

Emergency refresh correctly returned:

```text
passed_candidates=0
status=blocked_not_enough_fresh_candidates
```

### Read-only live rescan

A read-only `PUSH_MODE=ip DRY_RUN=1` live rescan over official Cloudflare IPs found no high-throughput candidates at that time:

```text
speed >= 10 MB/s candidates: 0/5
best cfst candidate: 172.66.147.91 at 9.13 MB/s
real 20MB retest minimum: 2.81 MB/s
```

The primary-slot guard blocked those candidates, which was correct.

### Recovery evidence

Later `validate-current` recovered without writing unsafe DNS:

```text
104.17.130.225 min 8.03 MB/s avg 8.33 MB/s
104.17.156.195 min 8.11 MB/s avg 8.22 MB/s
104.17.136.166 min 9.67 MB/s avg 9.71 MB/s
104.17.130.225 min 9.46 MB/s avg 9.64 MB/s
104.17.156.195 min 8.12 MB/s avg 8.38 MB/s
```

PC checks returned:

```text
youtube_http=204 youtube_total=1.51s
googlevideo_http=204 googlevideo_total=1.36s
```

DNS was verified against local resolver and 1.1.1.1 for `auto` through `auto4`.

## Code Changes

- Added `CFST_GUARD_REPAIR_STABLE_MIRROR=1`.
- Added emergency refresh report files:
  - `/root/cf-dns-speedup/emergency-refresh.latest.tsv`
  - `/root/cf-dns-speedup/emergency-refresh.validate.tsv`
- Added emergency refresh controls:
  - `CFST_EMERGENCY_REFRESH=1`
  - `CFST_EMERGENCY_REFRESH_APPLY=0`
  - `CFST_OBSERVE_EMERGENCY_REFRESH_APPLY=1`
  - `CFST_EMERGENCY_REFRESH_PRIMARY_MAX_MIN_SPEED=2`
  - `CFST_EMERGENCY_REFRESH_MIN_SPEED=6.5`
  - `CFST_EMERGENCY_REFRESH_CANDIDATES=8`
  - `CFST_EMERGENCY_REFRESH_ROUNDS=2`
  - `CFST_EMERGENCY_REFRESH_MIN_PASSED_SLOTS=3`
  - `CFST_EMERGENCY_REFRESH_MAX_UPDATES=5`
- Added `emergency-refresh` command.
- `observe-current` now runs emergency refresh after guard-repair, but only applies when `CFST_OBSERVE_EMERGENCY_REFRESH_APPLY=1` and fresh candidate validation passes.
- `run_once` only enforces primary-slot guard in `PUSH_MODE=domain`; read-only `PUSH_MODE=ip` diagnostics no longer fail solely because DNS-safe candidates are absent.

## Deployment

Router path: `/root/cf-dns-speedup`.

Backups:

```text
/root/openwrt-backup/cf-dns-speedup.sh.backup-20260628-220952-emergency-refresh
/root/openwrt-backup/run-regression-tests.sh.backup-20260628-220952-emergency-refresh
/root/openwrt-backup/config.env.backup-20260628-220952-emergency-refresh
/root/openwrt-backup/cf-dns-speedup.sh.backup-20260629-052006-readonly-guard-fix
/root/openwrt-backup/run-regression-tests.sh.backup-20260629-052006-readonly-guard-fix
```

Validation passed locally and on OpenWrt:

```text
bash -n cf-dns-speedup.sh
sh tests/run-regression-tests.sh
all regression tests passed
```

No PassWall restart, firewall change, token change, package change, or cron topology change was performed.

## Root Cause

The failure was a layered issue:

1. The protected stable primary IPs degraded severely during the evening.
2. Morning burst-speed candidates were not safe because they had no observation quorum and failed fresh evening validation.
3. Previous guard-repair behavior could be confused by failed-run candidate files and plan broad updates; stable-mirror repair closes that gap.
4. The project needs a faster live rescue scan because full `CFST_DOWNLOAD_COUNT=100` diagnostics can take too long during degraded periods.

## Next Optimization Recommendation

Phase 4 should add a fast rescue scan mode:

- Use smaller `CFST_DOWNLOAD_COUNT` such as 30-50 for emergency scans.
- Test both official and vetted external observation candidates.
- Require fresh 20MB validation minimum >= 6.5 MB/s before writing DNS.
- If no candidate passes, keep existing DNS and report `no_safe_replacement`.
- Optionally add a second fallback domain/pool outside the current official Cloudflare IP source for video peak hours.

This cannot guarantee perfect future 4K playback because Cloudflare path throughput is time-varying, but it prevents bad automatic replacements and gives the system a safe way to recover when fresh better candidates exist.
