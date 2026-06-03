# Stable Slot Policy Deployment

Date: 2026-06-03

## Problem

The 2026-06-03 morning run selected a healthy primary record but filled the backup records with bursty candidates:

```text
auto.greentraceifm.top  -> 104.17.158.242
auto1.greentraceifm.top -> 172.67.77.249
auto2.greentraceifm.top -> 172.67.79.52
auto3.greentraceifm.top -> 104.20.22.86
auto4.greentraceifm.top -> 172.67.79.166
```

Evening validation showed the primary was still usable, while the backup slots had degraded to roughly `0.30-1.33 MB/s`.

## Expert Review

The expert council approved a small reversible change:

- keep the existing primary safe mode;
- reserve the first backup slots for recently observed stable IPs;
- allow short-burst candidates only after the stable slots are filled;
- validate before any production DNS update;
- keep rollback simple by preserving the previous router script and config.

## Implementation

New defaults:

```sh
CFST_STABLE_SLOT_MODE=1
CFST_STABLE_SLOT_COUNT=3
CFST_STABLE_SLOT_MIN_SPEED="$CFST_PRIMARY_MIN_SPEED"
CFST_STABLE_SLOT_PREFER_REGEX="$CFST_PRIMARY_PREFER_REGEX"
CFST_STABLE_SLOT_AVOID_REGEX="$CFST_PRIMARY_AVOID_REGEX"
CFST_OBSERVATION_CANDIDATES=1
CFST_OBSERVATION_CANDIDATE_MIN_SPEED="$CFST_STABLE_SLOT_MIN_SPEED"
```

After stability retest sorting and primary safe-mode promotion, the script now promotes up to `CFST_STABLE_SLOT_COUNT` candidates that:

- pass the current stability retest;
- have enough successful retest rounds;
- have recent observation history;
- have no observed low-speed sample below the stable-slot floor;
- prefer `104.17.*` by default;
- avoid `104.20.*`, `104.26.*`, and `172.67.*` for stable slots unless there are not enough alternatives.

The stability candidate builder also injects observation-history candidates whose most recent observation still meets the stable-slot floor. Candidates with any historical low-speed observation are marked `observation_watch`; they can be retested and selected by real current speed, but they are not promoted into the protected stable slots. This keeps historically useful IPs available for retest even if the champion pool has been crowded out by morning burst candidates.

## Expected Effect

`auto`, `auto1`, and `auto2` should be biased toward stable video-throughput candidates. `auto3` and `auto4` can still carry challengers, but they should no longer displace stable backups when enough observed-stable IPs exist.

## Rollback

Restore the previous `cf-dns-speedup.sh` backup on the router, then run a read-only `health-check` before any DNS update.
