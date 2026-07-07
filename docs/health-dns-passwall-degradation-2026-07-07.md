# OpenWrt CFIP Health DNS and PassWall Degradation Repair

Date: 2026-07-07

## Summary

This change improves the safety and reliability of operational diagnosis for the OpenWrt Cloudflare preferred-IP project.

The current production bottleneck was not a Cloudflare DNS write error. DNS records for `auto` through `auto4` were consistent with Cloudflare after deployment. The remaining weak point was end-to-end PassWall node throughput: the current global node address was `auto1.greentraceifm.top`, and the latest PassWall node observation was `2.17 MB/s`, marked `degraded`.

## IT Expert Council Gate

Action Gate classified the OpenWrt, Cloudflare, PassWall, and credential-adjacent work as high risk. The approved implementation scope was reduced to:

- read-only checks before changes
- backup before deployment
- script/reporting/observability changes only
- no Cloudflare DNS mutation
- no PassWall restart, stop, or node switch
- no firewall, token, package, subscription, or automation-topology changes
- regression tests before and after deployment

## Implemented

- Added DNS health retry defaults:
  - `CFST_DNS_HEALTH_RETRIES=3`
  - `CFST_DNS_HEALTH_API_RETRIES=2`
  - `CFST_DNS_HEALTH_RETRY_SLEEP=1`
- Replaced fragile router DNS parsing with retry-based `router_dns_lookup_with_retries`.
- Made Cloudflare API health checks retry before reporting unavailable.
- Hardened Cloudflare health checks for unset token or zone variables under `set -u`.
- Added PassWall node degradation reporting:
  - command: `./cf-dns-speedup.sh passwall-node-degradation`
  - health-check section: `passwall-node-degradation`
  - reports current section, address, latest speed, latest status, consecutive degraded count, threshold, and status.
- Improved `passwall-stable-repair` dry-run output so a non-actionable state reports the current section and consecutive degraded count instead of `unknown`.
- Added regression tests for DNS retry parsing, PassWall consecutive degradation reporting, and stable-repair non-action explanation.

## Deployment Evidence

Pre-deployment:

```text
no_lock
predeploy_tests_rc=0
predeploy_health_rc=0
auto2.greentraceifm.top router_dns unresolved
auto2.greentraceifm.top cloudflare_api 104.17.136.166 ttl=60 proxied=false
```

Post-deployment:

```text
syntax_main_rc=0
syntax_observe_rc=0
postdeploy_tests_rc=0
postdeploy_health_rc=0
```

DNS health after retry parsing:

```text
auto.greentraceifm.top  router_dns 104.17.130.225  cloudflare_api 104.17.130.225
auto1.greentraceifm.top router_dns 104.17.156.195  cloudflare_api 104.17.156.195
auto2.greentraceifm.top router_dns 104.17.136.166  cloudflare_api 104.17.136.166
auto3.greentraceifm.top router_dns 104.17.130.225  cloudflare_api 104.17.130.225
auto4.greentraceifm.top router_dns 104.17.156.195  cloudflare_api 104.17.156.195
```

PassWall degradation report:

```text
section   address                  latest_speed_MBps latest_status consecutive_degraded threshold status
0FUdoZon  auto1.greentraceifm.top  2.17              degraded      1                    2         watch
```

Stable repair dry-run:

```text
name                    current_ip  desired_ip  action              reason
auto1.greentraceifm.top not_checked not_checked skip_not_degraded   current_section=0FUdoZon consecutive_degraded=1 need=2
updates=0
status=dry_run
```

## Rollback

Production backups were created before deployment:

```text
/root/openwrt-backup/cf-dns-speedup.sh.backup-20260707-201112-health-dns-passwall-degradation
/root/openwrt-backup/run-regression-tests.sh.backup-20260707-201112-health-dns-passwall-degradation
```

Rollback can restore those two files and rerun:

```sh
cd /root/cf-dns-speedup
bash -n ./cf-dns-speedup.sh
./tests/run-regression-tests.sh
./cf-dns-speedup.sh health-check
```

## Current Assessment

The project is safer to operate after this change because transient DNS or API read failures are less likely to create false alarms, and PassWall throughput degradation is now explicit in the health report.

This does not by itself force a node replacement. The current global node has one degraded observation, so the stable-repair gate correctly stayed in dry-run and did not update DNS. If the next observation also shows degraded throughput, the system will have enough evidence to consider a controlled stable-pool replacement rather than reacting to a single low sample.

## Recommended Next Step

Let the next scheduled PassWall node observation run. If `consecutive_degraded >= 2`, review `passwall-stable-repair` output and decide whether to enable a bounded repair window. Keep DNS mutation and PassWall restart disabled unless the repair plan is explicitly reviewed and approved.
