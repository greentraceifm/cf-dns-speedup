# Engineering Hardening Phase 1

Date: 2026-06-06

## Scope

This phase improves long-term stability without changing Cloudflare DNS selection thresholds, PassWall behavior, cron schedules, or test file size.

## Expert Council Decision

Do not perform a large rewrite yet. The project is already production-active on OpenWrt, so the first engineering hardening step should be small, reversible, and testable:

- add regression tests for the dual-pool selector and champion lifecycle fields
- add a read-only champion health report
- document future module boundaries before splitting the 2000+ line shell script

## Added Regression Coverage

`tests/run-regression-tests.sh` validates:

- stable preferred IPs stay ahead of short-lived burst-speed candidates
- stale IPs cannot enter the primary stable slots
- champion-pool lifecycle columns have consistent header/data width
- stable IPs retain `lifecycle_state=stable` and `promotion_ready=1`

The tests use TSV fixtures only and do not call Cloudflare, PassWall, curl, DNS, or the router network.

## Added Report

`./cf-dns-speedup.sh champion-report` is read-only and writes:

```text
/root/cf-dns-speedup/champion-report.latest.txt
```

The report includes:

- champion-pool summary counts
- `promotion_ready` IPs
- watch/stale/failing IPs
- Top10 by stable score
- recent lifecycle evictions

## Future Module Boundaries

Recommended next modules:

- `lib/config.sh`
- `lib/cfst.sh`
- `lib/cloudflare-dns.sh`
- `lib/champion-pool.sh`
- `lib/observation.sh`
- `lib/reporting.sh`
- `lib/health.sh`

Do not split all modules at once. Start with `champion-pool.sh` and `observation.sh` after regression tests have run cleanly for several normal update cycles.

## Safety

This phase is not intended to update DNS. Router validation should use:

```sh
sh -n /root/cf-dns-speedup/cf-dns-speedup.sh
./tests/run-regression-tests.sh
./cf-dns-speedup.sh champion-report
./cf-dns-speedup.sh health-check
```

Rollback:

```sh
cp /root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260606-engineering-phase1 /root/cf-dns-speedup/cf-dns-speedup.sh
```
