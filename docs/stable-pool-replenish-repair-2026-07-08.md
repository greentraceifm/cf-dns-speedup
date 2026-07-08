# OpenWrt CFIP Stable Pool Replenish and Controlled Repair

Date: 2026-07-08

## Summary

This deployment fixed a champion-pool blind spot, replenished the stable pool with fresh observations, and performed one bounded DNS repair for the degraded PassWall global slot.

The production issue was not Cloudflare DNS inconsistency. DNS health was correct after the previous repair. The active bottleneck was the PassWall global node using `auto1.greentraceifm.top`, with repeated end-to-end throughput near `2 MB/s`.

## IT Expert Council Gate

Action Gate classified OpenWrt, Cloudflare, PassWall, and credential-adjacent work as high risk. The approved implementation path was:

- read-only checks first
- backup before deployment and state mutation
- add tests before production deployment
- no PassWall restart
- no firewall, token, package, subscription, or cron-topology change
- DNS mutation allowed only as a single-record bounded stable-repair apply after dry-run gates passed

## Implemented

- `champion-refresh` command:
  - refreshes champion-pool state from existing observations
  - does not run speed tests
  - does not write DNS
- Champion-pool observation-only admission:
  - recent observation-only IPs can enter the champion pool
  - old observation-only IPs are not admitted into the pool
- Stable-pool replenish:
  - new command: `./cf-dns-speedup.sh stable-pool-replenish`
  - retests stable-pool `watch` candidates
  - writes fresh per-round observations to `observation-history.tsv`
  - refreshes `champion-pool.tsv`
  - does not write DNS
- Fresh pass governance:
  - a candidate that becomes `stable` after fresh passes has `fail_count` reset to `0`
- Stable-repair cooldown:
  - state file: `passwall-stable-repair.state.tsv`
  - default cooldown: `7200` seconds
  - prevents immediate reverse replacement after a successful stable repair

## Key Production Evidence

Before replenishment:

```text
passwall-node-degradation:
auto1.greentraceifm.top latest_speed=2.05 MB/s consecutive_degraded=3 status=needs_maintenance

stable repair dry-run:
blocked_insufficient_stable_pool stable_candidates=2 min_required=3
```

Stable-pool replenish retested three watch candidates:

```text
104.17.134.190  8.19 MB/s, 7.26 MB/s  pass/pass
104.17.156.195  8.12 MB/s, 9.31 MB/s  pass/pass
104.18.55.210   6.39 MB/s, 6.96 MB/s  low/pass
```

After `champion-refresh`:

```text
stable=4
promotion_ready=4
stable_pool=5
```

Bounded stable repair dry-run:

```text
auto1.greentraceifm.top 104.17.156.195 -> 104.17.134.190 update passwall_degraded_use_stable_pool
updates=1
```

Applied DNS repair:

```text
auto1.greentraceifm.top updated successfully:
104.17.156.195 -> 104.17.134.190
```

Post-apply DNS health:

```text
auto1.greentraceifm.top router_dns 104.17.134.190
auto1.greentraceifm.top cloudflare_api 104.17.134.190 ttl=60 proxied=false
```

Cooldown dry-run:

```text
auto1.greentraceifm.top 104.17.134.190 104.17.134.190 skip_cooldown old_ip=104.17.156.195 new_ip=104.17.134.190
updates=0
```

## Verification

Local:

```text
bash -n cf-dns-speedup.sh
bash -n lib/champion-pool.sh
bash -n passwall-node-observe.sh
./tests/run-regression-tests.sh
all regression tests passed
```

Router:

```text
syntax_main_rc=0
syntax_champion_lib_rc=0
tests_rc=0
health_rc=0
```

PC connectivity:

```text
youtube generate_204: HTTP 204, total about 2.8s
```

## Remaining Risk

The controlled DNS repair improved the selected IP path, but one immediate PassWall node check still measured only `4.09 MB/s`, below the `6.5 MB/s` target. This indicates the remaining bottleneck may be the PassWall endpoint, Oracle/Argo tunnel, or proxy path, not just the Cloudflare preferred IP.

Do not keep flipping `auto1` during the cooldown window. Let scheduled PassWall observations determine whether the new IP remains degraded.

## Next Step

Wait for the next scheduled `passwall-node-observe` run. If the node remains below threshold after cooldown and fresh observations, evaluate PassWall node benchmarking or endpoint-level repair as a separate high-risk change.
