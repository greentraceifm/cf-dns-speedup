# External candidate source experiment

Date: 2026-05-31

## Background

`cmliu/edgetunnel` appears fast mostly because it combines candidate aggregation, carrier-specific IP pools, and runtime connection racing. The runtime racing and proxy tunnel logic do not fit this OpenWrt DNS A-record updater. The safe piece to borrow is candidate-source expansion before local testing.

## Implemented Guardrails

- External candidates are disabled by default with `CFST_EXTERNAL_CANDIDATES=0`.
- `external-candidate-check` only writes `external-candidates.check.txt` and `external-candidates.report.txt`.
- The check command does not call `run_once`, does not stop or restart proxy services, does not update DNS, and does not write the champion pool.
- Runtime use creates a temporary merged IP file under `/tmp` and does not overwrite the production `ip.txt`.
- External candidates cannot update DNS unless `CFST_EXTERNAL_CANDIDATES_ALLOW_DNS=1` is explicitly set.
- External candidates cannot write the champion pool unless `CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION=1` is explicitly set.
- External URLs must be `https://`, must use an allowed host, and IP-literal/private/local hosts are rejected.
- ISP profiles are fixed to `cmcc`, `cu`, `ct`, or `cf` raw CIDR files from `cmliu/cmliu`.
- Downloads have byte, line, per-source, URL-count, and final candidate limits.
- Candidates are normalized and filtered to the configured IP version and Cloudflare ranges.
- IPv6 external candidates currently fail closed until exact IPv6 Cloudflare range validation is implemented.

## Recommended Experiment

Run only the check first:

```sh
CFST_EXTERNAL_CANDIDATES=1 CFST_ISP_PROFILE=cu bash ./cf-dns-speedup.sh external-candidate-check
```

If the check result looks reasonable, a non-DNS experiment can be run with:

```sh
PUSH_MODE=ip DRY_RUN=1 PROXY_PLUGIN=0 CFST_CHAMPION_POOL=0 CFST_EXTERNAL_CANDIDATES=1 CFST_ISP_PROFILE=cu bash ./cf-dns-speedup.sh run
```

Do not enable `CFST_EXTERNAL_CANDIDATES_ALLOW_DNS` or `CFST_EXTERNAL_CANDIDATES_ALLOW_CHAMPION` until several days of results show that external candidates consistently survive local 20 MB stability retests.
