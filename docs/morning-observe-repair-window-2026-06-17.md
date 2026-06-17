# OpenWrt CFIP Morning Observe Repair Window - 2026-06-17

## Summary

After Phase 3A-3, `observe-current` can automatically repair degraded exposed competitive slots. The remaining issue was timing: the 06:30 main run could expose new competitive IPs on `auto3` and `auto4`, but the first scheduled observation was still 14:30.

That left a morning exposure window where 4K playback could slow down before the auto-repair loop ran.

## Expert Council Decision

The approved low-risk change was to move the existing observation and repair loop earlier in the day, without changing speed-test parameters or the main DNS selection strategy.

Chosen schedule:

```text
30 8,10,14,20 * * *
```

This keeps the original afternoon and evening observations, and adds 08:30 and 10:30 checks after the 06:30 main preferred-IP run.

## Implementation

Updated router config:

```sh
CFST_OBSERVE_CRON="30 8,10,14,20 * * *"
```

Updated router crontab:

```text
30 6 * * * cd /root/cf-dns-speedup && /usr/bin/env bash ./cf-dns-speedup.sh >/tmp/cf-dns-speedup.cron.log 2>&1
30 8,10,14,20 * * * cd /root/cf-dns-speedup && /usr/bin/env bash ./cf-dns-speedup.sh observe-current >>/tmp/cf-dns-speedup.observe.log 2>&1
```

No PassWall restart was performed. No firewall, token, package, topology, Cloudflare credential, or speed-test parameter changes were made.

## Verification

Configuration syntax was corrected to Unix LF and validated:

```text
sh -n config.env
```

Health check showed:

```text
CFST_OBSERVE_GUARD_REPAIR_APPLY=1
CFST_OBSERVE_GUARD_REPAIR_MAX_UPDATES=2
CFST_OBSERVE_CRON="30 8,10,14,20 * * *"
lock=no_lock
PassWall running
```

Current DNS state after the morning run:

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
auto3 -> 104.26.13.136
auto4 -> 104.26.5.203
```

At health-check time, `auto3` and `auto4` were still above the exposed-slot threshold, so no immediate repair was required. If they degrade during the new 08:30 or 10:30 observation windows, the Phase 3A-3 auto-repair gate can now mirror them back to stable primary slots.

## Expected Effect

This reduces the practical exposure window for unstable competitive IPs from roughly 8 hours to about 2 hours after the 06:30 run. It directly targets the observed "morning 4K becomes slow around 9 AM" failure mode while preserving the stable-pool and competitive-pool architecture.
