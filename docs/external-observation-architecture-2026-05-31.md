# External Observation Architecture - 2026-05-31

## Decision

The project will not merge directly with `cmliu/edgetunnel`. The safe optimization is to borrow candidate-pool ideas while keeping `cf-dns-speedup` as a conservative OpenWrt DNS optimizer.

## Pool Model

The architecture now separates four pools:

- Production pool: IPs currently published in Cloudflare DNS.
- Champion pool: historically stable local winners.
- Local discovery pool: candidates from normal `cfst` runs.
- External observation pool: candidates from guarded external sources such as carrier-specific `cmliu` CIDR lists.

External candidates do not automatically update DNS and do not enter the champion pool unless explicitly allowed.

## New Commands

Run an isolated external observation pass:

```sh
bash ./cf-dns-speedup.sh external-observe
```

This command force-enables safe settings:

```text
PUSH_MODE=ip
DRY_RUN=1
PROXY_PLUGIN=0
CFST_CHAMPION_POOL=0
CFST_EXTERNAL_CANDIDATES=1
CFST_EXTERNAL_OBSERVATION_POOL=1
CFST_EXTERNAL_CANDIDATES_ALLOW_DNS=0
CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION=0
```

Show the observation pool:

```sh
bash ./cf-dns-speedup.sh observation-report
```

## Observation Pool

File:

```text
/root/cf-dns-speedup/external-observation-pool.tsv
```

Fields:

```text
ip
best_min_speed
best_avg_speed
recent_min_speed
pass_count
fail_count
consecutive_passes
consecutive_fails
first_seen
last_seen
source
status
```

Status values:

- `observing`: default state.
- `eligible_manual_review`: consecutive passes reached `CFST_EXTERNAL_PROMOTION_ROUNDS` and recent minimum speed meets `CFST_EXTERNAL_PROMOTION_MIN_SPEED`.
- `degraded`: consecutive failures reached `CFST_EXTERNAL_OBSERVATION_EVICT_FAILS`.

`eligible_manual_review` is only a review signal. It does not update DNS.

## Configuration

```sh
CFST_EXTERNAL_OBSERVATION_POOL=1
CFST_EXTERNAL_PROMOTION_ROUNDS=3
CFST_EXTERNAL_PROMOTION_MIN_SPEED=0
CFST_EXTERNAL_OBSERVATION_EVICT_FAILS=3
```

External candidates remain guarded by the existing controls:

```sh
CFST_EXTERNAL_CANDIDATES=0
CFST_EXTERNAL_CANDIDATES_ALLOW_DNS=0
CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION=0
```

## Promotion Policy

External candidates should be promoted manually only after multiple observation windows. A useful candidate should show:

- stable 20 MB retest results across several runs
- no repeated failed rounds
- no meaningful latency or jitter regression
- better recent minimum throughput than the current production pool
- no DNS update unless explicitly approved

## Expert Review

The expert review approved this design with these constraints:

- track consecutive passes and failures, not only lifetime totals
- sanitize TSV fields before writing reports
- merge records by IP
- force safe settings in `external-observe`
- rank reports by recent stable performance, not historical one-time best

