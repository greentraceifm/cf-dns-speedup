# PassWall Candidate Validation Deployment - 2026-07-09

## Summary

This deployment adds a real PassWall validation gate to candidate cultivation. Candidate IPs that look good in CloudflareST/direct stability tests are no longer trusted automatically. They can now be tested through the actual PassWall/Xray tunnel path using a non-primary test slot before being allowed to contribute to observation history and future stable-pool promotion.

## Why

On 2026-07-09, direct stability results showed several good-looking candidates, but real PassWall throughput remained around `4.x MB/s`. This proved that direct CloudflareST speed and real YouTube/PassWall throughput can diverge.

## Implemented

- New command:

```sh
./cf-dns-speedup.sh passwall-candidate-validate
```

- Default behavior is dry-run:
  - no DNS writes
  - no PassWall restart
  - no observation-history promotion

- Apply behavior requires:

```sh
CFST_PASSWALL_CANDIDATE_APPLY=1 ./cf-dns-speedup.sh passwall-candidate-validate
```

- Apply mode:
  - uses `auto4.greentraceifm.top` and PassWall section `RcklmTES` as the test slot by default
  - temporarily writes one candidate IP to the test DNS record
  - waits for DNS propagation
  - switches global PassWall node only for the test
  - measures the actual SOCKS/PassWall download speed
  - records resolved IP and result in `passwall-node-observation-history.tsv`
  - restores original DNS and original PassWall global node

## Safety Defaults

```text
CFST_PASSWALL_CANDIDATE_VALIDATE=1
CFST_PASSWALL_CANDIDATE_APPLY=0
CFST_PASSWALL_CANDIDATE_LIMIT=3
CFST_PASSWALL_CANDIDATE_RAW_LIMIT=20
CFST_PASSWALL_CANDIDATE_MIN_MBPS=6.5
CFST_PASSWALL_CANDIDATE_TEST_NAME=auto4.greentraceifm.top
CFST_PASSWALL_CANDIDATE_TEST_SECTION=RcklmTES
CFST_PASSWALL_CANDIDATE_DNS_WAIT_SECONDS=75
CFST_PASSWALL_CANDIDATE_RESTART_WAIT=10
```

`CFST_PASSWALL_CANDIDATE_RAW_LIMIT` intentionally fetches more raw candidates than the final test limit, then filters out recently low-throughput resolved IPs. This prevents a blocked top candidate from hiding lower-ranked candidates.

## Production Test Results

Tested through the real PassWall path on `auto4`:

```text
104.17.128.41   4.41 MB/s  low
104.17.143.183  4.61 MB/s  low
104.17.129.235  4.44 MB/s  low
```

All tested candidates were below the `6.5 MB/s` target, so none were appended as passing candidate observations and none were promoted into the stable pool.

## Validation

- Local syntax checks passed.
- Local regression tests passed.
- Router syntax checks passed.
- Router regression tests passed.
- Final router health:
  - no lock
  - PassWall running
  - `auto` to `auto4` router DNS matches Cloudflare API
  - global PassWall node restored to `auto.greentraceifm.top`
  - `passwall-candidate-validate` dry-run returns `no_candidates` after low-throughput candidates were filtered

## Current Status

The project is more correct and safer: high direct-speed candidates now need real PassWall proof before they can be cultivated. The current deployed set still does not meet the target real throughput for 4K; the tested candidate set was rejected rather than promoted.

## Next Step

Run the next normal observe/full scan cycle to discover fresh candidates. Any future candidate should be admitted only if it passes both:

- direct stability testing
- real PassWall candidate validation

