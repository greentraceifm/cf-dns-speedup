# OpenWrt CFIP Primary Slot Stability Guard

Date: 2026-06-10

## Incident

The `auto` Cloudflare preferred-IP route became too slow for stable 4K playback after the 2026-06-10 morning run.

Morning selected records:

```text
auto  -> 172.67.69.144
auto1 -> 172.67.79.54
auto2 -> 104.26.13.109
auto3 -> 104.26.3.215
auto4 -> 104.20.29.46
```

Morning stability looked good at about 15-16 MB/s, but afternoon validation collapsed:

```text
172.67.69.144 -> min 0.33 MB/s
172.67.79.54  -> min 0.38 MB/s
```

This was not a PassWall outage or Cloudflare DNS mismatch. The root cause was that short-lived burst-speed challenger IPs could still enter primary playback slots before enough observation history existed.

## Expert Council Decision

Action gate classified the change as high risk because it touches OpenWrt, Cloudflare DNS, and PassWall-adjacent deployment. User authorization was already given. The approved direction was:

- Pause Phase 2B modularization until runtime stability is restored.
- Protect `auto/auto1/auto2` from unobserved challenger IPs.
- Keep exploration in `auto3/auto4`, but do not let new burst-speed candidates control the main route.
- Prefer observed 104.17 stable candidates even when their speed is lower than a one-time 172.67 or 104.26 burst.

## Deployed Changes

Repository: `C:\Users\Leopold\cf-dns-speedup-repo`

Router path: `/root/cf-dns-speedup`

Backups:

```text
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260610-primary-guard
/root/cf-dns-speedup/config.env.backup-20260610-primary-guard
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260610-dryrun-override
/root/cf-dns-speedup/cf-dns-speedup.sh.backup-20260610-final-primary-guard
```

New defaults:

```sh
CFST_PRIMARY_FALLBACK_MIN_SPEED=6.5
CFST_PRIMARY_ALLOW_CHALLENGER=0
CFST_STABLE_SLOT_FALLBACK_MIN_SPEED=6.5
CFST_STABLE_SLOT_ALLOW_CHALLENGER=0
CFST_STABLE_SLOT_ALLOW_AVOID=0
```

Router `config.env` was updated with the primary guard settings.

`DRY_RUN_OVERRIDE` support was added so one-off verification can override a production `config.env` that contains `DRY_RUN=0`.

Regression coverage was extended to assert:

- stale IPs cannot enter primary slots
- avoid-family challenger IPs cannot enter primary slots
- unobserved challenger IPs cannot enter primary slots

## Current Result

After the controlled stability update, primary slots were restored:

```text
auto  -> 104.17.134.190
auto1 -> 104.17.130.225
auto2 -> 104.17.136.166
auto3 -> 172.67.69.144
auto4 -> 172.67.79.54
```

Validation at 2026-06-10 afternoon:

```text
104.17.134.190 -> min 8.62 MB/s, avg 8.72 MB/s
104.17.130.225 -> min 8.86 MB/s, avg 9.10 MB/s
104.17.136.166 -> min 9.08 MB/s, avg 9.45 MB/s
172.67.69.144  -> min 0.33 MB/s, avg 0.39 MB/s
172.67.79.54   -> min 0.38 MB/s, avg 0.42 MB/s
```

The first three records are now stable-slot candidates; the two collapsed burst candidates remain in competitive/observation slots only.

## Verification

Completed:

- `/root/cf-dns-speedup` has no lock
- `sh -n ./cf-dns-speedup.sh` passed
- `./tests/run-regression-tests.sh` passed
- `./cf-dns-speedup.sh validate-current` passed for primary slots
- `./cf-dns-speedup.sh health-check` shows PassWall running
- Cloudflare API and router DNS match for `auto` through `auto4` after cache settled

Important health-check observation:

```text
stable=1
watch=5
stale=4
promotion_ready=1
```

This means the immediate route is repaired, but the champion pool still needs more observation cycles to rebuild a deep stable bench.

## Follow-Up Plan

- Let the normal `observe-current` jobs run and watch whether `promotion_ready` rises to at least 2-3.
- Keep Phase 2B modularization paused until primary stability remains good through the next normal observe window and the next morning selection.
- Next hardening step: add a primary-slot quorum rule, requiring at least two recent observation passes before any new IP can enter `auto/auto1/auto2`.
- Do not increase test range or change the 20 MB test file until pool governance remains stable.

