# CFIP long-run deployment audit - 2026-07-22

## Scope and conclusion

The production chain was re-audited on the three involved hosts:

- `192.168.1.110`: Ubuntu/Docker Sidecar execution plane.
- `192.168.1.254`: OpenWrt/PassWall control and DNS plane.
- `192.168.1.140`: management jump host only; it is not required for scheduled operation.

The deployment is fit for continued unattended operation with fail-closed behavior. No production service was stopped, restarted, or switched during this work. Cloudflare DNS, candidate pools, PassWall nodes, firewall, routes, subscriptions, credentials, and scan limits were not changed.

One scheduling-level acceptance remains: the next natural Sidecar timer run around 2026-07-23 03:31 CST must produce a new complete report. Manual preflight and the low-traffic path check passed, but they do not replace a natural full cycle.

## Incident finding

The 2026-07-22 nightly Sidecar run exited at 03:34:59 CST before scanning or starting Xray:

```text
ERROR: sidecar ipvlan network is missing or invalid
ExecMainStatus=1
```

The host cleanup timer ran at 03:26:08 CST, eight minutes earlier. The previously active cleanup design allowed host-wide Docker pruning and could remove an intentionally idle Sidecar network and runtime image. The historical executable bytes were replaced during the recovery, so attribution is not cryptographically provable from the retained journal alone, but timing, the missing resources, and the old policy make this the high-confidence causal chain. No other active network-prune job was found.

Commit `3afdd54` had already replaced that policy and restored the resources before this audit. The deployed cleanup now:

- preserves all existing named networks and tagged images;
- prunes only old stopped containers and dangling images;
- limits BuildKit cache cleanup to the Engine API with a bounded timeout;
- verifies preserved resources after cleanup.

The current cleanup policy is classified as `preserve_idle_resources`.

## Bugs fixed

### Sidecar

- Validate `ipvlan_mode=l2`, not only driver, parent, subnet, and gateway.
- Compare the runtime image tag ID with `/var/lib/cfip-sidecar/runtime-image.id`.
- Reject non-IP path-probe bodies so an HTML error page cannot be treated as a public IP.
- Require an HTTPS path-probe URL.
- Yield while either Sub2API cleanup lock is held.
- Add connect and total timeouts to the BuildKit prune API call.
- Report the real systemd result, exit status, and latest report epoch.
- Correct an existing Sidecar config mode to `0600` during installation.

### OpenWrt

- Set `umask 077` for the main and PassWall observation scripts.
- Correct current and historical sensitive config files to mode `0600`.
- Explicitly set `CFST_ALLOW_PROXY_STOP=0` in production.
- Report PassWall runtime health from the Xray process and listeners `1070`, `1041`, `11400`, and `15353`, rather than treating enabled state as sufficient.
- Rotate the PassWall observation log at approximately 1 MiB.
- Rotate main logs during `observe-current`.
- Change the two observation cron wrappers from append to truncate for bounded `/tmp` logs.
- Fix the regression runner to use Bash and closed stdin, avoiding false failures or SSH test hangs.

## Production deployment

Sidecar deployment on `192.168.1.110`:

```text
backup=/var/backups/cfip-sidecar/long-run-hardening-20260722-013357
cfip-sidecar.sh=c4fae2d65ef88f660ebf9865db5efd44bf70838acc95800947d4a65d2af8fc97
sub2api-auto-cleanup.sh=a324ea7a38159b4b2acb2fff25caec8acd41dab98e40e14fc88d259d9753b315
```

OpenWrt deployment on `192.168.1.254`:

```text
backup=/root/openwrt-backup/cfip-long-run-hardening-20260722-093755
cf-dns-speedup.sh=23999cc2e7e6c6900c5608ca40484825599bd126191a542960327b860730a95e
passwall-node-observe.sh=918fd901b20b8bf79e459c4c76b5e1755438b9fe131b07aa9416742d57cca8e2
```

The config comparison excluding the two new safety keys was byte-equivalent. No non-safety setting changed.

## Verification

Code verification on Ubuntu:

- Sidecar test suite: pass.
- Full project regression suite: pass.
- Bash/sh syntax checks: pass.
- `git diff --check`: pass.

Runtime verification:

- Sidecar preflight: pass.
- Sidecar isolated path check: host and Sidecar exits are distinct.
- `cfip-direct`: `ipvlan|ens160|l2`, zero attachments after check.
- Runtime image identity: match.
- Docker PID remained `997`; four existing containers remained healthy.
- Ollama remained idle; no Sidecar container or Xray JSON residue remained.
- PassWall: enabled, two Xray processes, all four required listeners present.
- SmartDNS and dnsmasq remained running.
- PC, jump host, Sidecar host, and router Google/YouTube checks passed; a single router Google timeout was followed by three successful rounds and was classified as transient.
- Router DNS and Cloudflare API matched for `auto` through `auto4`.
- `192.168.1.1`, `192.168.1.254`, and `1.1.1.1` returned identical values for all five records.
- All discovered current and historical `config.env*` files are mode `0600`.
- All project and cleanup locks were free after deployment.

## Residual observations

Docker logged 50 DNS timeouts in the preceding 24 hours and 106 in 48 hours for the `sub2api` container querying `192.168.1.254:53`. Current container DNS resolution succeeds and all four containers are healthy. This is not the Sidecar ipvlan failure and did not justify restarting Docker or recreating containers during a no-outage change. Monitor it separately; remediation would require a dedicated DNS-path review and likely a container/Docker maintenance window.

The latest complete Sidecar report remains the 2026-07-21 CST cycle. Its five candidates returned HTTP 200, with minimum proxy throughput from 4.23 to 5.17 MB/s, all below the unchanged 6.5 MB/s real-path gate. No candidate was promoted and no DNS record was updated.

## Long-run behavior

The next natural sequence is:

1. Host cleanup runs around 03:19 CST under two maintenance locks.
2. Sidecar runs around 03:31 CST and yields before testing if either cleanup lock is still held.
3. Sidecar validates network mode, image identity, resource health, independent path, and Xray cleanup before writing a report.
4. Sidecar exports competition-only candidates; it never updates Cloudflare DNS or stable pools.
5. OpenWrt observations continue at 08:30/10:30/14:30/20:30 and PassWall path observations at 09:05/15:05/21:05.
6. The disabled 06:30 and 15:30 proxy-stopping jobs remain disabled.

A Sidecar failure can therefore skip one observation, but it cannot stop or restart PassWall. Stable/auto promotion still requires the unchanged real PassWall minimum of 6.5 MB/s.
