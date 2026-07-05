# Candidate cultivation and stable repair - 2026-07-05

## Expert review

Recommendation: implement the idea in two stages:

1. Cultivate more stable IPs from high-throughput challengers.
2. Use stable-pool DNS repair only after repeated PassWall endpoint degradation.

Do not directly auto-switch PassWall nodes during daily observation. Node switching remains a maintenance-window action through `passwall-node-benchmark`.

## Candidate cultivation

`observe-current` now does more than retest current DNS. It also selects up to three high-throughput non-current candidates from the latest stability result and champion pool, validates each with one real download round, and appends the result to `observation-history.tsv`.

Defaults:

```text
CFST_CANDIDATE_CULTIVATION=1
CFST_CANDIDATE_CULTIVATION_LIMIT=3
CFST_CANDIDATE_CULTIVATION_MIN_SPEED=10
CFST_CANDIDATE_CULTIVATION_ROUNDS=1
```

Report:

```text
/root/cf-dns-speedup/candidate-cultivation.latest.tsv
```

The champion pool is refreshed after new observations are appended. Promotion is still governed by existing quorum and lifecycle rules, so one fast run does not immediately enter the stable primary path.

## Stable repair

New command:

```sh
./cf-dns-speedup.sh passwall-stable-repair
```

It reads `passwall-node-observation-history.tsv`. If the current PassWall auto-family section has consecutive degraded observations, it maps the current PassWall address back to its DNS record and plans a one-record Cloudflare DNS replacement from stable `promotion_ready` champion-pool candidates.

Defaults:

```text
CFST_PASSWALL_STABLE_REPAIR=1
CFST_PASSWALL_STABLE_REPAIR_APPLY=0
CFST_PASSWALL_STABLE_REPAIR_DEGRADED_COUNT=2
CFST_PASSWALL_STABLE_REPAIR_MIN_SPEED=6.5
CFST_PASSWALL_STABLE_REPAIR_MIN_STABLE=3
CFST_PASSWALL_STABLE_REPAIR_MAX_UPDATES=1
```

Report:

```text
/root/cf-dns-speedup/passwall-stable-repair.latest.tsv
```

Default status is dry-run. DNS writes require `CFST_PASSWALL_STABLE_REPAIR_APPLY=1` and are bounded to one update.

## Daily observation integration

`passwall-node-observe.sh` still performs the 5MB read-only endpoint check. After writing the observation history row, it runs `passwall-stable-repair` in dry-run mode by default. This creates a repair plan when conditions are met, without restarting PassWall or changing DNS.

## Safety boundaries

- No PassWall restart.
- No full CFST scan.
- No firewall, token, package, subscription, or topology change.
- No DNS write unless explicit apply is enabled.
- Stable-pool repair is blocked when fewer than three stable promotion-ready candidates exist.
- Challenger IPs are cultivated through observation first; they do not directly replace production DNS.

## Verification

Regression tests cover:

- Candidate cultivation validates high-throughput challengers.
- Current DNS IPs are not duplicated in cultivation checks.
- Stable repair plans a bounded one-slot replacement after consecutive degraded PassWall observations.
- Existing dual-pool, guard-repair, emergency refresh, champion lifecycle, and PassWall benchmark tests still pass.
