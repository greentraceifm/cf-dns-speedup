# PassWall node daily observe deployment - 2026-07-05

## Expert review

Recommendation: deploy low-frequency read-only PassWall endpoint observation, not automatic node switching.

Reasoning:

- `passwall-node-check` is safe for daily observation because it does not restart PassWall and does not change DNS or UCI config.
- `passwall-node-benchmark` should remain a maintenance-window repair command because it switches nodes and restarts PassWall.
- Daily observation should use a smaller file than manual repair benchmarks to avoid competing with user traffic.

## Deployment

Installed wrapper:

```text
/root/cf-dns-speedup/passwall-node-observe.sh
```

Scheduled cron:

```cron
5 9,15,21 * * * cd /root/cf-dns-speedup && /usr/bin/env sh ./passwall-node-observe.sh >>/tmp/cf-dns-speedup.passwall-node-observe.log 2>&1
```

Runtime behavior:

- Read-only.
- Does not restart PassWall.
- Does not update Cloudflare DNS.
- Does not change firewall, package, token, subscription, or topology.
- Skips if `/tmp/cf-dns-speedup.lock` exists.
- Uses an independent lightweight lock at `/tmp/cf-dns-speedup-passwall-node-observe.lock`.
- Downloads 5MB through the current PassWall SOCKS path.

Reports:

```text
/root/cf-dns-speedup/passwall-node-benchmark.latest.tsv
/root/cf-dns-speedup/passwall-node-observation-history.tsv
/root/cf-dns-speedup/passwall-node-observe.log
```

## Controls

Defaults used by the wrapper:

```text
CFST_PASSWALL_NODE_TEST_URL=https://speed.cloudflare.com/__down?bytes=5242880
CFST_PASSWALL_NODE_CONNECT_TIMEOUT=8
CFST_PASSWALL_NODE_TIMEOUT=35
```

Manual maintenance benchmark remains explicit:

```sh
CFST_PASSWALL_NODE_APPLY=1 ./cf-dns-speedup.sh passwall-node-benchmark
```

## Expected impact

At three runs per day, traffic is about 15MB/day plus HTTP overhead. It should not materially affect router performance or user traffic. The command provides early evidence when YouTube 4K slowness comes from the PassWall proxy path rather than Cloudflare DNS preferred IPs.
