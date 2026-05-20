# OpenWrt Deployment Notes - 2026-05-20

## Current Deployment

- Device: OpenWrt/Kwrt at `192.168.1.254`
- Install path: `/root/cf-dns-speedup`
- Runtime script: `/root/cf-dns-speedup/cf-dns-speedup.sh`
- Config file: `/root/cf-dns-speedup/config.env` (not committed; contains Cloudflare secrets)
- Cron: `30 6 * * * cd /root/cf-dns-speedup && /usr/bin/env bash ./cf-dns-speedup.sh >/tmp/cf-dns-speedup.cron.log 2>&1`
- Mode: `PUSH_MODE=domain`, `DOMAIN_UPDATE_MODE=one_to_one`, `CDN_IP_MODE=official`, `PROXY_PLUGIN=1`, `DRY_RUN=0`
- Speed test URL: `https://greentrace-speedtest.pages.dev/10mb.bin`

## Managed DNS Records

The production OpenWrt task currently updates these A records:

- `auto.greentraceifm.top`
- `auto1.greentraceifm.top`
- `auto2.greentraceifm.top`
- `auto3.greentraceifm.top`
- `auto4.greentraceifm.top`

Latest controlled validation run on 2026-05-20 completed successfully and updated the records to:

- `auto.greentraceifm.top -> 104.26.0.180`
- `auto1.greentraceifm.top -> 104.26.6.221`
- `auto2.greentraceifm.top -> 172.67.79.60`
- `auto3.greentraceifm.top -> 172.67.65.236`
- `auto4.greentraceifm.top -> 172.67.76.16`

## Safety Enhancements

The OpenWrt deployment now includes:

- A lock directory at `/tmp/cf-dns-speedup.lock` to prevent overlapping cron/manual runs.
- Exit cleanup that attempts to restart the selected proxy service if the script exits after stopping it.
- Log rotation for `run.log` and `cfst-output.log`; defaults are `LOG_MAX_KB=1024` and `LOG_KEEP_DAYS=14`.
- Run summaries written to `last-run.summary` and `last-run.json` after real runs.
- Raw `cfst` progress redirected to `cfst-output.log` for non-interactive cron runs.

## Validation Checklist

Use these commands after deployment or after a router reboot:

```sh
cd /root/cf-dns-speedup
bash -n cf-dns-speedup.sh
crontab -l | grep cf-dns-speedup
ls -ld /tmp/cf-dns-speedup.lock 2>/dev/null || echo no_lock
/etc/init.d/passwall enabled && echo passwall_enabled=yes
/etc/init.d/smartdns status
/etc/init.d/dnsmasq status
/etc/init.d/firewall status
cat last-run.summary 2>/dev/null || true
tail -n 80 run.log
```

From a LAN client, verify DNS convergence:

```powershell
Resolve-DnsName auto.greentraceifm.top -Server 192.168.1.254
Resolve-DnsName auto1.greentraceifm.top -Server 192.168.1.254
Resolve-DnsName auto2.greentraceifm.top -Server 192.168.1.254
Resolve-DnsName auto3.greentraceifm.top -Server 192.168.1.254
Resolve-DnsName auto4.greentraceifm.top -Server 192.168.1.254
```

## Rollback

A backup was left on the OpenWrt device before the latest compatibility fix:

- `/root/cf-dns-speedup/cf-dns-speedup.sh.bak.2026-05-20-224847`

Rollback command:

```sh
cd /root/cf-dns-speedup
cp -p cf-dns-speedup.sh.bak.2026-05-20-224847 cf-dns-speedup.sh
chmod 755 cf-dns-speedup.sh
bash -n cf-dns-speedup.sh
```

## Notes

- The controlled validation run on 2026-05-20 temporarily stopped PassWall for the speed test, then restarted it successfully.
- OpenWrt does not necessarily provide GNU coreutils such as `paste`; the script avoids that dependency.
- Keep `config.env` only on the router. Do not commit Cloudflare API tokens, Zone IDs, or personal notification tokens.