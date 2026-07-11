# External Observation Promotion and Real-Path Gate - 2026-07-11

## Summary

This no-outage change fixes candidate cultivation without changing DNS, cron,
PassWall state, firewall rules, credentials, or the active node.

The review found two separate throughput layers:

- Direct Cloudflare retests still produced about `7.24-9.36 MB/s`.
- The active PassWall path produced `2.03 MB/s` in a fresh 5 MB check, while
  the previous observation was `1.84 MB/s` with eight consecutive degraded
  samples.

The bottleneck is therefore the real proxy path, not a lack of direct-speed
champion records. The `6.5 MB/s` real-path gate remains unchanged.

## Defect Fixed

External observations used `CFST_EXTERNAL_PROMOTION_ROUNDS=3` for two different
purposes:

1. a single observation was required to report at least three successful
   internal download rounds;
2. the candidate then needed three consecutive successful observations.

Production uses two internal stability rounds, so condition 1 could never be
met. External candidates were permanently classified as failures even when
both rounds passed at more than 8 MB/s.

The logic now separates the dimensions:

- `CFST_EXTERNAL_OBSERVATION_MIN_OK_ROUNDS=2`: minimum successful downloads
  inside one observation;
- `CFST_EXTERNAL_PROMOTION_ROUNDS=3`: number of consecutive successful
  observations required before manual real-path review.

## Safety Gates Added

- Eligible external observations are fed only into
  `passwall-candidate-validate`.
- They never write DNS or enter the production champion pool directly.
- `passwall-candidate-validate` still defaults to dry-run and still requires
  at least `6.5 MB/s` through the real PassWall path before cultivation.
- `passwall-stable-repair` now requires a candidate's latest real-path record
  in the recent history window to be HTTP 200, status `ok`, and at least
  `6.5 MB/s`.
- A direct-only stable candidate is no longer sufficient for an automatic
  repair plan.

## Verification

Local Git Bash:

```text
bash -n cf-dns-speedup.sh
bash -n tests/run-regression-tests.sh
./tests/run-regression-tests.sh
all regression tests passed
```

Router staging and production:

```text
sh -n ./cf-dns-speedup.sh
sh -n ./tests/run-regression-tests.sh
sh ./tests/run-regression-tests.sh </dev/null
all regression tests passed
```

Post-deployment evidence:

```text
PassWall: running
router DNS auto..auto4: matches Cloudflare API
lock: none
stable champions: 5
stale champions: 0
promotion_ready: 5
real-qualified stable repair candidates: 0
stable repair: blocked_insufficient_stable_pool
candidate validation: dry_run
```

The normal 09:05 PassWall observation then produced a newer end-to-end sample:

```text
auto current PassWall speed: 0.67 MB/s, degraded
stable repair: stable_candidates=0, blocked_insufficient_stable_pool
PassWall: remained running
lock: none
```

This scheduled sample did not change DNS or restart PassWall. It confirms that
the real proxy path is still deteriorating while the new gate prevents an
unqualified automatic replacement.

The dry-run candidate queue contained only:

```text
104.17.146.59
104.18.55.210
```

No candidate was tested through a temporary DNS slot during this deployment.

## Rollback

Router backup:

```text
/root/openwrt-backup/cf-dns-speedup-external-promotion-real-gate-20260711-0901
```

Rollback is file-only: restore `cf-dns-speedup.sh`, `config.example.env`, and
`tests/run-regression-tests.sh` from that directory. No service restart is
required for the script rollback itself.

## Remaining Bottleneck

The project still has no candidate that has demonstrated at least `6.5 MB/s`
through the real PassWall path. Broader external observation can now cultivate
candidates correctly, but it must run at low frequency and each candidate must
still pass real-path validation before it can influence `auto`.

The daily 06:30 scan also stopped PassWall for about 23 minutes. That is a
separate availability risk and should be redesigned as a no-outage scan path
before changing the schedule or selection thresholds.

## Records

- GitHub implementation commit: `5d0886a`.
- Notion append marker: `2026-07-11 External observation promotion and real-path gate`.
- OpenClaw memory:
  `/home/ubuntu/.openclaw/workspace/memory/openwrt-cfip-external-observation-real-path-gate-2026-07-11.md`.
- Local memory:
  `docs/openwrt-cfip-external-observation-real-path-gate-2026-07-11.md` in the Codex memory backup workspace.
