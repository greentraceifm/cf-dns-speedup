# Proxy-stop safety gate (2026-07-18)

## Incident

The 06:30 unattended full preferred-IP run stopped PassWall before the CFST
speed test. The stop began at about 06:30 and PassWall was restarted around
06:51, so routed traffic and Codex API access were interrupted for roughly
twenty minutes. The Sidecar was not the direct cause.

## Policy

`CFST_ALLOW_PROXY_STOP` defaults to `0`. The main `run` path and
`stability-update` path fail closed before any speed-test preparation when a
proxy plugin is selected. The stop helper repeats the same check, protecting
future call sites. Setting `CFST_ALLOW_PROXY_STOP=1` is reserved for a
supervised maintenance window and is not part of unattended configuration.

The no-outage Sidecar remains the production discovery path. A blocked legacy
run must not update DNS or pools.

## Deployment state

The router 06:30 legacy cron entry was disabled after the incident. No
PassWall, DNS, firewall, route, token, subscription, or unrelated service was
changed by this code change. The existing backup for the cron edit is:

`/root/openwrt-backup/cfip-cron-disable-20260718-115609`

The code change is safe to roll back by restoring the previous script and
example configuration from the recorded Git commit; the explicit gate should
remain enabled until the Sidecar path has passed its observation window.

## Verification

The deployed router script SHA256 is
`519ec7d519ed5add6429157e6efd53cfe523fc1ab829dd0429dd2eb96340e560`.
The pre-change script backup is
`/root/openwrt-backup/cfip-proxy-stop-gate-20260718-202319`; the intermediate
backup before the final entry preflight is
`/root/openwrt-backup/cfip-proxy-stop-gate-20260718-203441`.

The 06:30 legacy cron remains disabled. Xray PIDs remained `18010` and `18923`
through deployment, required listener ports remained present, and router/PC
Google and YouTube checks returned HTTP 204. `auto` through `auto4` matched
across 192.168.1.1, 192.168.1.254, and 1.1.1.1. Full regression tests passed.
Cloudflare API was not separately rechecked.

## Separate Sidecar observation

The 2026-07-18 03:32 CST Sidecar timer run failed before scanning because the
public-IP probe to `www.cloudflare.com:443` timed out. The three prior nightly
reports (July 14-16) were complete; the timer remains active, all four existing
containers are healthy, no Sidecar container or Xray JSON remains, and the
Sidecar host currently returns HTTP 204 for Google and YouTube. This transient
Sidecar failure did not stop PassWall and did not cause the 06:30 outage.
