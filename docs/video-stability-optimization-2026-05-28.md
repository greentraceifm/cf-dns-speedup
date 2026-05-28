# Video Stability Optimization - 2026-05-28

## Expert Review Summary

Scope: improve the stability of the final five Cloudflare IPs used by the OpenWrt `cf-dns-speedup` production task.

Council conclusion:

- SRE view: make one reversible change at a time, keep PassWall/DNS health checks after each run, and preserve a router-side backup before changing production config.
- Security view: do not expose or rotate Cloudflare tokens, do not paste `config.env`, and avoid unnecessary Cloudflare DNS writes during experiments.
- Verification view: first expand the download-tested candidate pool from `50` to `100` while keeping the known-good `10mb.bin` object. Only switch to `20mb.bin` after the `dn=100` result is compared.

## Current Production Baseline

Latest GitHub baseline:

```text
be3fe8f Tune Cloudflare IP selection for video throughput
```

Known production profile before this optimization:

```text
CFST_THREADS=16
CFST_COUNT=5
CFST_DOWNLOAD_COUNT=50
CFST_RESULT_COUNT=5
CFST_TOTAL_TIMEOUT=2400
CFST_DOWNLOAD_TIMEOUT=20
CFST_MAX_LATENCY=200
CFST_URL=https://greentrace-speedtest.pages.dev/10mb.bin
PROXY_PLUGIN=1
DRY_RUN=0
```

## Stage 1: Wider Candidate Pool

Recommended production-candidate profile:

```text
CFST_THREADS=16
CFST_COUNT=5
CFST_DOWNLOAD_COUNT=100
CFST_RESULT_COUNT=5
CFST_TOTAL_TIMEOUT=3600
CFST_DOWNLOAD_TIMEOUT=25
CFST_MAX_LATENCY=220
CFST_URL=https://greentrace-speedtest.pages.dev/10mb.bin
PROXY_PLUGIN=1
DRY_RUN=0
```

Reasoning:

- The 2026-05-25 deep test showed that increasing the download queue to `50` found materially faster IPs than the original small queue.
- If the final five IPs are unstable, the next likely improvement is a broader candidate pool, not a larger file first.
- Keeping `10mb.bin` isolates the variable: the only major change is candidate breadth.

## Stage 2: Larger Object, Only If Needed

If Stage 1 still produces unstable video playback, test:

```text
CFST_DOWNLOAD_COUNT=100
CFST_RESULT_COUNT=5
CFST_TOTAL_TIMEOUT=4200
CFST_DOWNLOAD_TIMEOUT=30
CFST_MAX_LATENCY=220
CFST_URL=https://greentrace-speedtest.pages.dev/20mb.bin
```

Reasoning:

- A 20MB object better approximates sustained transfer than 10MB.
- It also increases run time and Cloudflare Pages traffic, so it should be a second-stage test rather than the first production change.

## Required Router-Side Procedure

Before changing `/root/cf-dns-speedup/config.env`:

```sh
cd /root/cf-dns-speedup
stamp="$(date +%Y%m%d-%H%M%S)"
cp -p config.env "config.env.bak.video-stability-${stamp}"
cp -p cf-dns-speedup.sh "cf-dns-speedup.sh.bak.video-stability-${stamp}"
bash -n cf-dns-speedup.sh
```

After a test run:

```sh
cd /root/cf-dns-speedup
cat last-run.summary 2>/dev/null || true
tail -n 80 run.log
ls -ld /tmp/cf-dns-speedup.lock 2>/dev/null || echo no_lock
/etc/init.d/passwall enabled && echo passwall_enabled=yes
/etc/init.d/smartdns status
/etc/init.d/dnsmasq status
```

Rollback config:

```sh
cd /root/cf-dns-speedup
cp -p config.env.bak.video-stability-YYYYMMDD-HHMMSS config.env
chmod 600 config.env
bash -n cf-dns-speedup.sh
```

## Acceptance Criteria

- Script syntax check passes.
- Lock file is released after the run.
- PassWall remains enabled after the run.
- SmartDNS and dnsmasq report healthy status.
- `last-run.summary` reports success.
- Top five selected records do not regress badly versus the previous profile across at least two runs, ideally one evening run and one morning run.
