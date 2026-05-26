# Cloudflare IP Optimization Test Review - 2026-05-25

## Scope

Target: OpenWrt router `192.168.1.254`, project `/root/cf-dns-speedup`.

Goal: explain why optimized Cloudflare IP updates do not necessarily improve video playback speed, and identify safe next tests.

## Expert Council Review

Selected lenses:

- OpenClaw SRE Reviewer: keep checks reversible, preserve PassWall/DNS health, compare evidence instead of changing production first.
- OpenClaw Security Reviewer: do not expose Cloudflare tokens, do not update DNS or change firewall/service state during diagnosis.
- Feynman-style verification: split the claim into testable mechanics: candidate IP range, speed-test URL, DNS use path, proxy path, and video path.

Approved test boundary:

- Allowed: SSH read-only checks, dry-run `PUSH_MODE=ip`, temp output under `/tmp`, no DNS update.
- Allowed: `PROXY_PLUGIN=0` during tests so PassWall is not stopped/restarted.
- Not allowed without explicit approval: production DNS changes, token changes, firewall changes, cron changes, PassWall stop/restart tests.

## Tests Run

### Production Baseline

Latest production run:

- Time: `2026-05-25 06:30:00` to `06:38:04`
- Mode: `domain`, `one_to_one`, `official`, `DRY_RUN=0`
- Proxy handling: `proxy_service=passwall` stopped/restarted by the script
- Status: `success`

Top 5 production results:

```text
172.67.71.103   77.06 ms   8.88 MB/s
172.67.68.83    76.50 ms   7.92 MB/s
172.67.75.192   77.42 ms   7.66 MB/s
104.20.23.93    77.30 ms   7.58 MB/s
172.67.78.188   77.67 ms   7.48 MB/s
```

### Official Dry-Run, No PassWall Stop

Command style: temp `APP_DIR`, `PUSH_MODE=ip`, `DRY_RUN=1`, `PROXY_PLUGIN=0`, no production DNS change.

Candidate list:

- Mode: `official`
- Input count: Cloudflare official IPv4 list, about `3583` candidates
- Result count: top `10`

Top results:

```text
172.67.71.26    78.25 ms   2.89 MB/s
172.67.70.190   78.11 ms   1.90 MB/s
104.26.4.98     78.58 ms   0.45 MB/s
172.67.68.236   79.23 ms   0.39 MB/s
172.67.69.237   79.00 ms   0.39 MB/s
104.26.5.120    78.66 ms   0.37 MB/s
172.67.77.126   77.96 ms   0.34 MB/s
172.67.76.152   78.02 ms   0.33 MB/s
104.20.29.120   77.80 ms   0.31 MB/s
104.20.31.105   78.15 ms   0.31 MB/s
```

Interpretation: when PassWall is not stopped, same style of official-IP test is much slower than the production 06:30 run. This may be due to PassWall routing, time-of-day congestion, or both. It is not proof that DNS selection alone is bad.

### Reverse Dry-Run

Mode: `reverse`, `PUSH_MODE=ip`, `DRY_RUN=1`, `PROXY_PLUGIN=0`.

Result: failed before speed test.

Cause:

```text
https://zip.baipiao.eu.org -> HTTP 502
https://cf.yg-kkk.gq      -> HTTP 502
```

Interpretation: reverse IP mode currently depends on unstable third-party source URLs. Do not promote it to production until source freshness and availability are solved.

### Official Dry-Run, With PassWall Stop/Restart

Approved follow-up test after user confirmation.

Command style: temp `APP_DIR`, `PUSH_MODE=ip`, `DRY_RUN=1`, `PROXY_PLUGIN=1`, no production DNS change. This follows production proxy handling: stop PassWall before speed test, restart it after speed test, then wait 30 seconds.

Run:

- Time: `2026-05-25 21:54:11` to `22:05:29`
- Mode: `official`
- Input count: `3583` official IPv4 candidates
- Status: `success`
- Post-check: PassWall enabled, SmartDNS running, dnsmasq running, no lock remained

Top results:

```text
104.26.6.219    78.60 ms   1.14 MB/s
104.20.24.27    78.31 ms   0.42 MB/s
172.67.74.23    78.28 ms   0.39 MB/s
104.26.7.77     78.97 ms   0.35 MB/s
104.26.3.254    78.69 ms   0.34 MB/s
172.67.76.73    78.10 ms   0.33 MB/s
104.26.5.107    78.97 ms   0.32 MB/s
172.67.71.20    78.54 ms   0.31 MB/s
172.67.66.179   77.88 ms   0.31 MB/s
172.67.77.6     77.92 ms   0.29 MB/s
```

Interpretation: stopping PassWall during the evening test did not improve throughput. It was slower than the immediately preceding no-stop dry-run and much slower than the early-morning production run. This points more toward time-of-day congestion, Cloudflare Pages/test-object variability, or upstream path variation than a simple PassWall bottleneck.

## Health After Tests

- No `/tmp/cf-dns-speedup*.lock` remained.
- `passwall` remains enabled.
- `smartdns` and `dnsmasq` reported running.
- No production DNS update was performed by the tests.

## Findings

1. Current production script is functioning and updates the five `auto*.greentraceifm.top` records successfully.
2. The production speed test is not equivalent to video playback speed. It measures a Cloudflare Pages `10mb.bin` file against candidate IPs.
3. Video speed may be limited by PassWall routing, proxy node throughput, video platform CDN path, DNS rule matching, time-of-day congestion, or the fact that video traffic is not actually using the `auto*` records.
4. Reverse mode is not ready as a production optimization because both configured reverse-list sources returned `HTTP 502`.
5. Same-evening PassWall stop/restart did not reproduce the early-morning speed. PassWall is not proven to be the main bottleneck.
6. The current production `CFST_COUNT=5` means `cfst` only download-tests the first 5 latency-ranked candidates. It does not prove those 5 are the best throughput candidates among the full official list.

### Official Deep Dry-Run, `-dn 50 -p 50`

Approved follow-up test after user confirmation.

Command style: direct `cfst` run under `/tmp/cf-dns-speedup-test-dn50`, no DNS update, stop/restart PassWall for production-comparable routing. Parameters:

```text
-tp 443 -t 4 -n 16 -dn 50 -p 50 -tl 300 -tll 0 -sl 0 -dt 20
```

Run:

- Time: `2026-05-25 22:20:55` to `22:35:50`
- Status: `success`
- Post-check: PassWall enabled, SmartDNS running, dnsmasq running, no lock remained

Top results:

```text
104.17.157.175   191.42 ms   6.07 MB/s
104.17.148.45    193.12 ms   5.65 MB/s
104.17.141.149   178.82 ms   5.61 MB/s
104.17.144.176   180.09 ms   5.45 MB/s
104.17.149.130   148.80 ms   5.41 MB/s
104.17.139.212   184.51 ms   5.35 MB/s
104.17.137.243   180.96 ms   5.33 MB/s
104.17.158.33    182.33 ms   5.29 MB/s
104.17.150.157   181.87 ms   5.11 MB/s
162.159.237.223  167.05 ms   5.08 MB/s
```

Latency-bucket observations:

```text
Best <=100 ms: 104.20.21.204  79.36 ms  3.12 MB/s
Best <=150 ms: 104.17.149.130 148.80 ms 5.41 MB/s
Best <=200 ms: 104.17.157.175 191.42 ms 6.07 MB/s
```

Interpretation: expanding the download-test queue from 5/10 to 50 found materially higher-throughput IPs in the same evening window. However, most of the fastest results are higher-latency `104.17.*` candidates around `175-193 ms`. For video throughput this may be better; for latency-sensitive browsing it may feel worse.

## Recommended Next Tests

1. Split `CFST_COUNT` into two knobs: `CFST_DOWNLOAD_COUNT` and `CFST_RESULT_COUNT`.
2. Use a video-throughput profile: `CFST_DOWNLOAD_COUNT=50`, `CFST_RESULT_COUNT=5`, `CFST_MAX_LATENCY=200`.
3. Keep `<=150 ms` as an optional interactive/balanced profile, but this run showed the 4K-oriented top 5 candidates are mostly in the `150-200 ms` range.
4. Test a realistic video-path URL or large sustained object, not only the 10 MB Pages file.
5. Verify whether the actual video workflow resolves or routes through `auto*.greentraceifm.top`.
6. Compare morning, afternoon, and evening results before changing production strategy.
7. Improve reverse-mode source reliability before testing it again.

## Production Update - 2026-05-25

Implemented script change:

- Added `CFST_DOWNLOAD_COUNT` for download-test queue size.
- Added `CFST_RESULT_COUNT` for final displayed/DNS-updated result count.
- Kept legacy `CFST_COUNT` as the fallback for both new knobs when they are not configured.

Production OpenWrt config after update:

```text
CFST_THREADS=16
CFST_COUNT=5
CFST_DOWNLOAD_COUNT=50
CFST_RESULT_COUNT=5
CFST_TOTAL_TIMEOUT=2400
CFST_DOWNLOAD_TIMEOUT=20
CFST_MAX_LATENCY=200
PROXY_PLUGIN=1
DRY_RUN=0
```

Backups on router:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.bak.dn50.20260525-224523
/root/cf-dns-speedup/config.env.bak.dn50.20260525-224523
/root/cf-dns-speedup/config.env.bak.video200.20260525-230040
```

Production verification run:

- Time: `2026-05-25 23:01:36` to `23:18:19`
- Status: `success`
- DNS update mode: `one_to_one`
- Post-check: PassWall enabled, SmartDNS running, dnsmasq running, no lock remained.

Selected production IPs:

```text
auto.greentraceifm.top   -> 104.17.138.99    174.55 ms   6.50 MB/s
auto1.greentraceifm.top  -> 104.17.142.128   180.51 ms   6.45 MB/s
auto2.greentraceifm.top  -> 162.159.237.205  183.58 ms   5.80 MB/s
auto3.greentraceifm.top  -> 104.17.130.173   177.39 ms   5.49 MB/s
auto4.greentraceifm.top  -> 104.17.147.59    175.91 ms   5.37 MB/s
```

Operational note: an earlier verification attempt used command-line environment overrides, but `config.env` takes precedence after loading, so it ran as production mode. The final state was corrected by switching to the video-throughput `200 ms` profile and running a successful production update.
