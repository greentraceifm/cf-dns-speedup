# PassWall auto-family node benchmark deployment - 2026-07-05

## Incident

`auto.greentraceifm.top` could not play YouTube 4K smoothly even though the Cloudflare preferred IP guard did not report a DNS collapse.

## IT expert review

Decision: treat this as an end-to-end proxy path incident, not a pure Cloudflare DNS incident.

Safety boundaries:

- Do not change Cloudflare DNS, tokens, firewall, packages, subscriptions, or topology.
- Benchmark only the existing PassWall auto-family nodes.
- Back up `/etc/config/passwall` before switching nodes.
- Keep the fastest working node; if all candidates fail, restore the original node.
- Add an observable command so future incidents show whether the bottleneck is DNS/IP or PassWall proxy throughput.

## Evidence

Morning DNS update failed safely because primary-slot guard blocked quorum-pending candidates. Current DNS remained on stable `104.17.*` addresses.

`validate-current` after repair showed selected Cloudflare IPs were still acceptable:

```text
104.17.130.225 min 8.98 MB/s avg 9.09 MB/s
104.17.156.195 min 8.16 MB/s avg 8.57 MB/s
104.17.136.166 min 7.42 MB/s avg 8.12 MB/s
104.17.130.225 min 7.99 MB/s avg 8.68 MB/s
104.17.156.195 min 9.30 MB/s avg 9.35 MB/s
```

PassWall SOCKS end-to-end throughput was much lower:

```text
current node: OEotWIjI auto3.greentraceifm.top:443
20MB SOCKS test: 4.50 MB/s
status: degraded, below 6.5 MB/s target
```

## Manual repair performed

Benchmarked existing 443 auto-family nodes:

```text
4gimRsru auto.greentraceifm.top  4.58 MB/s
0FUdoZon auto1.greentraceifm.top 4.54 MB/s
aInFoVtC auto2.greentraceifm.top 4.39 MB/s
OEotWIjI auto3.greentraceifm.top 4.76 MB/s
RcklmTES auto4.greentraceifm.top 3.96 MB/s
```

Selected `OEotWIjI` / `auto3.greentraceifm.top:443` as the best available 443 node.

Tested existing 8443 auto-family nodes; all failed the SOCKS download test and were not selected.

Backups on router:

```text
/root/openwrt-backup/passwall.backup-20260705-103400-auto-node-benchmark
/root/openwrt-backup/passwall.backup-20260705-103703-auto-node-benchmark-8443
/root/openwrt-backup/cf-dns-speedup.sh.backup-20260705-104756-passwall-node-benchmark
/root/openwrt-backup/run-regression-tests.sh.backup-20260705-104756-passwall-node-benchmark
```

## Code changes

Added PassWall endpoint observability and controlled benchmark commands:

```sh
./cf-dns-speedup.sh passwall-node-check
CFST_PASSWALL_NODE_APPLY=1 ./cf-dns-speedup.sh passwall-node-benchmark
```

New report:

```text
/root/cf-dns-speedup/passwall-node-benchmark.latest.tsv
```

Default benchmark candidates:

```text
4gimRsru 0FUdoZon aInFoVtC OEotWIjI RcklmTES
```

Main controls:

```text
CFST_PASSWALL_NODE_APPLY=0|1
CFST_PASSWALL_NODE_MIN_MBPS=6.5
CFST_PASSWALL_NODE_TEST_URL=https://speed.cloudflare.com/__down?bytes=20971520
CFST_PASSWALL_NODE_SECTIONS="4gimRsru 0FUdoZon aInFoVtC OEotWIjI RcklmTES"
CFST_PASSWALL_NODE_RESTART_WAIT=15
```

## Verification

Local:

```text
bash -n cf-dns-speedup.sh: passed
./tests/run-regression-tests.sh: passed
```

Router:

```text
bash -n ./cf-dns-speedup.sh: passed
bash ./tests/run-regression-tests.sh: passed
./cf-dns-speedup.sh passwall-node-check: status=degraded, report generated
```

## Root cause

The immediate 4K issue was not caused by a bad Cloudflare DNS selection. DNS/IP validation stayed around 7.4-9.35 MB/s, while the real PassWall SOCKS path was only about 4.5 MB/s. The bottleneck shifted to the selected PassWall proxy node and/or upstream proxy path.

## Remaining risk

This deployment improves diagnosis and selects the best existing auto-family node, but it cannot guarantee 4K when every existing PassWall auto-family node is below target. A complete long-term fix needs either better upstream nodes or scheduled endpoint benchmarks that can select from a larger, proven node set.
