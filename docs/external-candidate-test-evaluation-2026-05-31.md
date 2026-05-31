# External Candidate Test Evaluation - 2026-05-31

## Scope

This record covers the first isolated test of the guarded external candidate source logic added in commit `4375927`.

The test was read-only for production:

- `DRY_RUN=1`
- `PROXY_PLUGIN=0`
- `CFST_CHAMPION_POOL=0`
- `CFST_EXTERNAL_CANDIDATES_ALLOW_DNS=0`
- `CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION=0`
- no Cloudflare DNS update
- no PassWall stop/start
- no production `ip.txt`, `result.csv`, or champion pool overwrite

## Production Baseline

Command:

```sh
cd /root/cf-dns-speedup && bash ./cf-dns-speedup.sh validate-current
```

Result:

```text
ip                min_speed_mbps  avg_speed_mbps  ok_rounds
162.159.237.177   7.09            7.58            2
104.17.134.190    9.75            9.90            2
104.17.131.81     8.12            8.16            2
104.17.128.154    7.92            8.40            2
104.17.156.195    9.25            9.50            2
```

## External Candidate Source Check

Profile `cu` accepted two CIDR ranges:

```text
104.26.0.0/20
172.67.64.0/20
```

Additional profile source availability:

```text
cu    accepted_count=2
cmcc  accepted_count=3
ct    accepted_count=1
cf    accepted_count=7
```

## Isolated External Candidate Run

Temporary test directory:

```text
/tmp/cf-dns-speedup-external-test-20260531195722
```

Main test settings:

```sh
CFST_ISP_PROFILE=cu
CDN_IP_MODE=official
CFST_URL=https://greentrace-speedtest.pages.dev/20mb.bin
CFST_DOWNLOAD_COUNT=100
CFST_DOWNLOAD_COUNT_STEP=0
CFST_DOWNLOAD_COUNT_MAX=100
CFST_RESULT_COUNT=5
CFST_PREFER_MIN_SPEED=10
CFST_STABILITY_TEST_COUNT=12
CFST_STABILITY_TEST_ROUNDS=2
```

The run merged 2 external CIDRs into the runtime candidate file only:

```text
base candidates: 3583
merged runtime candidates: 3586
```

Top `cfst` initial result:

```text
104.17.139.129  21.83 MB/s
```

Post stability retest top 5:

```text
ip              latency_ms  cfst_speed_mbps  min_speed_mbps  avg_speed_mbps
104.17.143.77   141.72      20.17            9.87            9.95
104.17.146.131  157.12      15.69            9.85            9.88
104.17.135.221  149.56      16.37            9.65            9.73
104.17.139.129  172.45      21.83            8.90            8.97
104.17.157.221  150.97      16.02            8.57            8.98
```

## Expert Review Summary

The expert review approved the test method and safety controls. The review found that the new logic can discover usable high-throughput candidates, but this run did not produce a production replacement that clearly beats the current champion group after stability retesting.

Key points:

- External candidate import is useful as discovery input.
- Initial `cfst` throughput can be much higher than the final stable throughput.
- Stability retest remains mandatory before any production DNS update.
- Current production group should be retained.
- External candidates should remain default-off or observation-only until multi-window tests prove consistent advantage.

## Conclusion

The new external candidate project can find additional fast-looking IPs, including candidates with initial throughput above 20 MB/s. However, after real download stability retesting, the best external candidates were roughly comparable to the current production group and did not justify replacing the active DNS records.

Decision:

- keep current production DNS group unchanged
- keep external candidates guarded and disabled by default
- use external candidates as a supplemental discovery pool
- run future comparisons across multiple time windows before promoting any external candidate

