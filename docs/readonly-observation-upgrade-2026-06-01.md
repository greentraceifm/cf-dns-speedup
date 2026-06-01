# Read-only observation upgrade, 2026-06-01

## Purpose

Add daytime/evening observation without automatic DNS changes, proxy restarts, or champion-pool writes.

## Changes

- `validate-current` now verifies the real current Cloudflare DNS records first. It only falls back to locally selected rows if DNS records cannot be read.
- `stability-verify` writes to `result.stability.verify.tsv` instead of overwriting the production `result.stability.tsv`.
- `observe-current` runs current-DNS validation and appends rows to `observation-history.tsv`.
- `install-observe-cron` installs a read-only observation cron using `CFST_OBSERVE_CRON`.
- Added `CFST_CHAMPION_FAIL_MIN_SPEED`, defaulting to `CFST_RETAIN_MIN_SPEED`, so champion-pool failure tracking follows the video-throughput floor instead of only the hard degradation floor.
- Raised default `CFST_FINAL_CANDIDATE_LIMIT` from 20 to 30 to leave room for current DNS, champion pool, and new challengers.

## Safety boundary

The observation path does not update Cloudflare DNS, restart PassWall, reload services, write the champion pool, or mutate external candidate settings.

Approved use:

```sh
bash ./cf-dns-speedup.sh observe-current
bash ./cf-dns-speedup.sh install-observe-cron
```

Default schedule:

```text
30 14,20 * * *
```

## Deployment Result

Deployed on OpenWrt `/root/cf-dns-speedup` on 2026-06-01 CST.

Installed read-only cron:

```text
30 14,20 * * * cd /root/cf-dns-speedup && /usr/bin/env bash ./cf-dns-speedup.sh observe-current >>/tmp/cf-dns-speedup.observe.log 2>&1
```

Verification:

- `observe-current` appended to `observation-history.tsv`.
- `stability-verify` wrote `result.stability.verify.tsv`.
- Production `result.stability.tsv` hash was unchanged.
- `champion-pool.tsv` hash was unchanged.
- DNS and PassWall were not mutated by the observation path.

Latest verification top 5 from `result.stability.verify.tsv`:

```text
104.17.151.5    min 9.79 MB/s
104.17.134.190  min 9.77 MB/s
104.17.156.195  min 9.16 MB/s
104.17.158.242  min 8.47 MB/s
104.17.128.154  min 8.45 MB/s
```
