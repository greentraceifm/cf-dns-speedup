# Champion retention deployment record

Date: 2026-05-31

## Deployment

- GitHub commit: `12a9363 Add champion IP retention`
- OpenWrt host: `192.168.1.254`
- Project path: `/root/cf-dns-speedup`
- Router backup:
  - `/root/openwrt-backup/cf-dns-speedup-champion-2026-05-31-121332`
  - `/root/openwrt-backup/cf-dns-speedup-champion-fix-2026-05-31-121437`
- Deployed script SHA-256: `7afe1323adb73fe01b3e65f61f76f114d0d7264fe063876ce7f1cb18e2e201c2`

## Runtime settings

```sh
CFST_DOWNLOAD_COUNT=100
CFST_DOWNLOAD_COUNT_STEP=0
CFST_DOWNLOAD_COUNT_MAX=100
CFST_RESULT_COUNT=5
CFST_PREFER_MIN_SPEED=10
CFST_URL=https://greentrace-speedtest.pages.dev/20mb.bin
CFST_STABILITY_TEST_COUNT=12
CFST_STABILITY_TEST_ROUNDS=2
CFST_COMPARE_CURRENT_DNS=1
CFST_CHAMPION_POOL=1
CFST_CHAMPION_POOL_SIZE=10
CFST_RETAIN_RATIO=0.90
CFST_REPLACE_IMPROVE_RATIO=1.25
CFST_DEGRADE_MIN_SPEED=2
CFST_FAIL_EVICT_COUNT=3
CFST_FINAL_CANDIDATE_LIMIT=20
PROXY_PLUGIN=1
DRY_RUN=0
```

## DNS restored to stable group

```text
auto.greentraceifm.top  -> 162.159.237.177
auto1.greentraceifm.top -> 104.17.134.190
auto2.greentraceifm.top -> 104.17.131.81
auto3.greentraceifm.top -> 104.17.128.154
auto4.greentraceifm.top -> 104.17.156.195
```

## Validation

- Local `bash -n`: passed.
- Local `git diff --check`: passed.
- Remote `bash -n`: passed.
- `health-check`: passed; router DNS and Cloudflare API agreed after TTL refresh.
- `validate-current`: passed without stopping PassWall or updating DNS.

Latest `validate-current` result:

```text
ip               min MB/s   avg MB/s   ok_rounds
162.159.237.177  7.99       8.00       2
104.17.134.190   8.32       8.55       2
104.17.131.81    7.97       8.15       2
104.17.128.154   7.27       8.10       2
104.17.156.195   8.62       9.14       2
```

## Notes

- `stability-update` still stops and restarts PassWall because it can update DNS.
- `validate-current` is the read-only verification mode and does not stop PassWall.
- No token, password, cookie, or SSH key is stored in this record.

