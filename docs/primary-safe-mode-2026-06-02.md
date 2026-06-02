# Primary safe mode, 2026-06-02

## Problem

The 2026-06-02 06:30 run succeeded, but `auto.greentraceifm.top` was updated to `104.20.22.86`.

Morning stability retest showed:

```text
104.20.22.86 min 10.94 MB/s
```

At 09:08 CST, current validation showed it had degraded:

```text
104.20.22.86 min 0.61-2.04 MB/s
```

PassWall was using `auto.greentraceifm.top` as the main TCP node and HAProxy balancing was disabled, so the degraded primary record directly affected YouTube 4K playback.

## Immediate Fix

Updated only the Cloudflare DNS record:

```text
auto.greentraceifm.top 104.20.22.86 -> 104.17.134.190
```

No PassWall restart was performed. After DNS TTL/cache expiry, both router-local DNS and public DNS resolved `auto.greentraceifm.top` to `104.17.134.190`.

Post-fix validation:

```text
104.17.134.190 min 8.96 MB/s avg 9.46 MB/s
104.17.158.242 min 8.40 MB/s avg 9.11 MB/s
104.17.151.5   min 8.89 MB/s avg 9.29 MB/s
104.17.156.195 min 9.23 MB/s avg 9.23 MB/s
```

## Code Change

Added primary safe mode:

```sh
CFST_PRIMARY_SAFE_MODE=1
CFST_PRIMARY_MIN_SPEED=8
CFST_PRIMARY_PREFER_REGEX='^104\.17\.'
CFST_PRIMARY_AVOID_REGEX='^(104\.20\.|104\.26\.|172\.67\.)'
```

`stability-verify` confirmed the safe-mode sort keeps a stable `104.17.*` IP in the first slot while preserving other fast candidates in the remaining slots.

Verification boundary:

- `result.stability.tsv` hash unchanged during `stability-verify`.
- `champion-pool.tsv` hash unchanged during `stability-verify`.
- No DNS update, PassWall restart, or champion-pool mutation during verification.
