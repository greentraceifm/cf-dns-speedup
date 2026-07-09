# PassWall Real Throughput Feedback Deployment - 2026-07-09

## Summary

On 2026-07-09, the preferred-IP project showed a mismatch between CloudflareST/champion-pool scores and real PassWall proxy throughput. The champion pool still looked healthy, but all deployed `auto` to `auto4` PassWall nodes measured below the operational target.

This deployment adds a feedback loop from real PassWall node throughput back into stable-repair candidate selection, so recently low-throughput resolved IPs are not blindly reused by DNS repair.

## Evidence

- `auto.greentraceifm.top` was updated from `104.17.130.225` to `104.17.136.166` by a bounded stable repair.
- DNS propagated successfully:
  - `auto.greentraceifm.top` router DNS and Cloudflare API both resolved to `104.17.136.166`.
- Real PassWall download tests remained degraded:
  - `auto`: about `4.63 MB/s`, resolved IP `104.17.136.166`
  - `auto1`: about `4.42 MB/s`, resolved IP `104.17.134.190`
  - `auto2`: about `4.47 MB/s`, resolved IP `104.17.136.166`
  - `auto3`: about `4.40 MB/s`, resolved IP `104.17.130.225`
  - `auto4`: about `4.50 MB/s`, resolved IP `104.17.156.195`
- Final read-only check showed current node around `4.27 MB/s`, still below the `6.5 MB/s` PassWall target.
- `passwall-stable-repair` dry-run after feedback history:
  - normal cooldown: `updates=0`
  - cooldown disabled for simulation: `blocked_insufficient_stable_pool stable_candidates=1 min_required=3`

## Root Cause

The immediate issue was not just a bad DNS record. The stable/champion pool was scored mostly from direct CloudflareST and observation data, while YouTube/4K experience depends on real PassWall end-to-end proxy throughput.

Several IPs that looked stable by direct testing were slow when used through the actual PassWall node path. Without feedback from PassWall measurements, stable repair could keep rotating among IPs that were already proven slow in the real proxy path.

## Changes Deployed

- Added `resolved_ip` capture to `passwall-node-observe.sh`.
- Added history migration for old `passwall-node-observation-history.tsv` rows that did not have `resolved_ip`.
- Added `passwall_resolve_ipv4`, `ensure_passwall_node_history_file`, and `passwall_append_node_history_row` to `cf-dns-speedup.sh`.
- Updated `passwall-node-benchmark` so every applied node benchmark appends:
  - section
  - address
  - measured speed
  - status
  - resolved IP
- Added stable-repair protection:
  - recently replaced IP quarantine, default `86400` seconds
  - recent low-throughput resolved IP exclusion, default last `24` PassWall history rows
- Added regression tests for:
  - recently replaced IP quarantine
  - recent low-throughput resolved IP exclusion
  - node benchmark appending resolved-IP throughput history

## Validation

- Local Git Bash:
  - `bash -n cf-dns-speedup.sh`
  - `bash -n passwall-node-observe.sh`
  - `bash -n tests/run-regression-tests.sh`
  - `./tests/run-regression-tests.sh`
  - result: all regression tests passed
- Router:
  - syntax checks passed
  - regression tests passed
  - PassWall node benchmark wrote resolved-IP history
  - stable repair dry-run produced `updates=0`
  - no lock after validation

## Backups

- `/root/openwrt-backup/cf-dns-speedup-stable-repair-20260709-083906`
- `/root/openwrt-backup/passwall-node-benchmark-primary-20260709-084323`
- `/root/openwrt-backup/passwall-node-benchmark-allslots-20260709-084543`
- `/root/openwrt-backup/cf-dns-speedup-passwall-feedback-20260709-085208`
- `/root/openwrt-backup/cf-dns-speedup-passwall-history-20260709-085635`

## Current Status

The project is safer: it now refuses to promote or repair toward recently observed low-throughput PassWall IPs. However, current real proxy throughput is still below the desired 4K target, because the deployed candidate set does not currently contain enough real PassWall high-throughput IPs.

## Next Step

The next optimization should be candidate cultivation with real PassWall validation:

- keep CloudflareST as the broad pre-filter
- test only shortlisted candidates through the actual PassWall path
- admit an IP into stable pool only after it passes direct testing and real PassWall throughput
- keep the existing guard that blocks DNS writes when fewer than three stable real-throughput candidates remain

