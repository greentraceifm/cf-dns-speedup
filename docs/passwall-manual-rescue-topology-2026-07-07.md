# PassWall Manual Rescue Topology Repair - 2026-07-07

## Incident Summary

The PC could not use the `auto` node reliably for external access. The operator manually switched the PassWall global TCP node to `auto1.greentraceifm.top`, which restored access.

Read-only checks showed:

- The preferred-IP DNS slots were not corrupted by the morning run.
- `validate-current` still measured the selected Cloudflare IPs around the acceptable range.
- YouTube DNS had recovered to Google addresses and `generate_204` returned HTTP 204 from the PC.
- PassWall global TCP node was manually set to the `auto1` section.
- `passwall.@acl_rule[1]` is a scoped override for `192.168.1.110`, not the PC at `192.168.1.100`.
- A stale `/tmp/cf-dns-speedup.lock` from an interrupted diagnostic run blocked safe follow-up checks and was removed only after its PID was confirmed dead.

## Root Cause

The project did not clearly report the difference between:

- the global PassWall node actually used by the PC, and
- the scoped ACL node used only by a specific device.

Older `passwall-node-benchmark` behavior also changed `acl_rule[1]` while benchmarking global node candidates. That was unsafe because a maintenance benchmark could unintentionally overwrite a device-specific force-proxy rule.

## Repair

- Added `passwall-node-topology` reporting.
- Added topology output to `health-check`.
- Added topology metadata to `passwall-node-check`.
- Updated `passwall-node-observe.sh` so routine observation logs the actual global node being measured and the ACL topology status.
- Changed `passwall_set_tcp_node` so benchmarking preserves `acl_rule[1]` by default.
- Added explicit `CFST_PASSWALL_NODE_SYNC_ACL1=1` escape hatch for rare maintenance cases where global and ACL1 must intentionally be synchronized.
- Added regression coverage for scoped ACL overrides and ACL preservation during node benchmark.

## Deployment Verification

Deployed to `/root/cf-dns-speedup` on 2026-07-07.

Post-deploy checks:

- `bash -n ./cf-dns-speedup.sh`: pass.
- `sh -n ./passwall-node-observe.sh`: pass.
- `./tests/run-regression-tests.sh`: pass.
- `./cf-dns-speedup.sh health-check`: pass.
- Router DNS and Cloudflare API matched for `auto` through `auto4`.
- `validate-current` measured current DNS slots around 8.05-9.80 MB/s.
- PassWall topology status: `scoped_override`.
- Global PassWall node: `auto1.greentraceifm.top`.
- ACL1 remains scoped to `192.168.1.110` and still points to `auto3.greentraceifm.top`.
- No `/tmp/cf-dns-speedup.lock` or passwall observe lock remained after checks.
- PC YouTube `generate_204` recovered to HTTP 204 after the maintenance benchmark restart window.

Maintenance benchmark result:

```text
auto   4.41 MB/s
auto1  4.60 MB/s  selected
auto2  4.41 MB/s
auto3  4.48 MB/s
auto4  4.53 MB/s
```

The selected node is still below the 6.5 MB/s target, so the remaining 4K risk is PassWall endpoint throughput, not Cloudflare preferred-IP DNS corruption.

## Safety Boundary

This repair does not:

- update Cloudflare DNS,
- restart or stop PassWall,
- change firewall rules,
- change tokens or subscriptions,
- change package versions,
- expand the preferred-IP scan range.

## Operational Guidance

For daily observation, use:

```sh
./cf-dns-speedup.sh passwall-node-check
./cf-dns-speedup.sh passwall-node-topology
```

For maintenance-window node switching:

```sh
CFST_PASSWALL_NODE_APPLY=1 ./cf-dns-speedup.sh passwall-node-benchmark
```

By default this changes only the global PassWall node and preserves source-bound ACL rules.

Only use the following when intentionally aligning ACL1 to the selected global node:

```sh
CFST_PASSWALL_NODE_SYNC_ACL1=1 CFST_PASSWALL_NODE_APPLY=1 ./cf-dns-speedup.sh passwall-node-benchmark
```

## Rollback

Restore the previous scripts from Git or from the router backup copied before deployment. If a PassWall config rollback is needed, restore the latest known-good file under `/root/openwrt-backup/` and restart PassWall during a maintenance window.
