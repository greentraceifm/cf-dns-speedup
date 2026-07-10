# PassWall Candidate Source Floor Fix - 2026-07-10

## Summary

The 2026-07-10 evening review confirmed that the project could still find direct CloudflareST candidates, but the real PassWall path remained the bottleneck.

Two small fixes were deployed:

- `passwall-candidate-validate` now has its own source threshold, `CFST_PASSWALL_CANDIDATE_SOURCE_MIN_SPEED`, defaulting to `CFST_PASSWALL_CANDIDATE_MIN_MBPS` (`6.5`).
- The apply loop now reads candidates through a dedicated file descriptor so measurement commands cannot accidentally consume the candidate list stdin.

This keeps the important safety rule unchanged: a candidate is only cultivated when it passes the real PassWall throughput gate.

## Evidence

External observe ran in dry-run mode from `2026-07-10 20:31:42` to `20:56:20`.

It did not update DNS, did not write the champion pool as a production result, and did not stop PassWall. Direct results found several candidates above the PassWall target:

```text
104.17.143.101 direct stability min 8.57 MB/s
104.17.132.91  direct stability min 8.81 MB/s
104.17.149.50  direct stability min 8.38 MB/s
104.21.225.64  direct stability min 8.44 MB/s
```

Before the fix, `passwall-candidate-validate` dry-run returned `no_candidates` because the generic candidate cultivation source floor still defaulted to `10 MB/s`.

After the fix, dry-run planned candidates correctly:

```text
104.17.132.91
104.17.143.101
104.21.225.64
104.17.149.50
```

Real PassWall validation rejected all tested candidates:

```text
104.17.132.91   4.58 MB/s  low
104.17.143.101  4.41 MB/s  low
104.21.225.64   3.89 MB/s  low
104.17.149.50   4.68 MB/s  low
```

No candidate reached the `6.5 MB/s` real PassWall gate, so none should be promoted or cultivated as stable.

## Deployed Changes

- `cf-dns-speedup.sh`
  - Added `CFST_PASSWALL_CANDIDATE_SOURCE_MIN_SPEED`.
  - Temporarily applies that source floor only while building PassWall validation candidates.
  - Restores the previous generic cultivation limit and source floor after candidate extraction.
  - Uses fd `3` for the apply candidate loop so subprocess stdin reads cannot skip later candidates.

- `tests/run-regression-tests.sh`
  - Added coverage for candidates below the generic `10 MB/s` cultivation floor but above the PassWall validation source floor.
  - Added a stdin-consuming measurement mock to verify multi-candidate apply does not skip candidates.

## Validation

Local Git Bash:

```text
bash -n cf-dns-speedup.sh
bash -n tests/run-regression-tests.sh
./tests/run-regression-tests.sh
all regression tests passed
```

Router:

```text
sh -n ./cf-dns-speedup.sh
sh -n ./tests/run-regression-tests.sh
./tests/run-regression-tests.sh </dev/null
all regression tests passed
```

Final router health at `2026-07-10 21:19:39`:

```text
no cfst/cf-dns-speedup process
no lock
PassWall running
auto..auto4 router DNS matches Cloudflare API
global PassWall node restored to auto.greentraceifm.top
auto current PassWall speed: 1.84 MB/s, degraded, consecutive_degraded=8
champion summary: total=10 stable=5 watch=2 stale=0 promotion_ready=5
```

## Backups

```text
/root/openwrt-backup/cf-dns-speedup-passwall-candidate-source-floor-20260710-210045
/root/openwrt-backup/cf-dns-speedup-passwall-candidate-fd-loop-20260710-210551
/root/openwrt-backup/passwall.backup-20260710-210200-candidate-validate
/root/openwrt-backup/passwall.backup-20260710-210706-candidate-validate
```

## Current Bottleneck

The current bottleneck is upstream/real PassWall path throughput. Direct CloudflareST and direct stability retest can still show `8.x MB/s`, but the same IPs only delivered about `3.9-4.7 MB/s` through the actual PassWall path.

The guard is doing the right thing: it refuses to promote these candidates even though they look acceptable in direct tests.

## Next Step

Do not lower the real PassWall gate. The next useful optimization is a broader, low-frequency candidate source search that feeds only into `passwall-candidate-validate`, or an alternate real-path test source/profile. Any candidate still needs to pass the `6.5 MB/s` real PassWall gate before cultivation or stable-pool promotion.
