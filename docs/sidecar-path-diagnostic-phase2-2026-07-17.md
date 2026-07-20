# Sidecar Path Diagnostic Phase 2 - 2026-07-17

## Decision

The three-night observation gate completed with 15 valid candidate samples.
All downloads returned HTTP 200, but none reached the existing real-path gate
of 6.5 MB/s.

Aggregate evidence:

- direct discovery average: 8.419 MB/s
- Sidecar Xray minimum-speed average: 4.281 MB/s
- proxy/direct average ratio: 51.0%
- candidates at or above 6.5 MB/s: 0 of 15
- Pearson correlation between direct and proxy speed: -0.050

The evidence does not support expanding the normal candidate scan beyond 100
or increasing the object size as the next optimization. The current bottleneck
is more likely in the Xray/upstream profile path than in Cloudflare-IP
discovery.

## Expert Review

The engineering, SRE, security, and falsifiability review approved a bounded
diagnostic mode with these conditions:

- manual-only; the nightly timer must continue to invoke only `observe`
- one IPv4 reference candidate, no direct scan
- four serial scenarios with two 20 MB rounds each (about 160 MB total)
- run only in a quiet maintenance window after all existing resource gates pass
- no PassWall stop, restart, switch, or configuration change
- no DNS, Cloudflare, champion-pool, stable-pool, firewall, credential, or timer mutation
- no automatic promotion regardless of the result
- abort on a held lock, active Ollama model, high load, unhealthy dependency,
  invalid network isolation, or missing encrypted credential

The strongest objection was temporal noise: a four-scenario sequence is not a
perfect simultaneous experiment. The first run is therefore diagnostic
evidence, not a permanent tuning decision. A large effect should be repeated
on another night before changing resource policy.

## Diagnostic Matrix

The `diagnose IPv4` command runs the following matrix:

| Scenario | Xray target | Xray CPU | curl CPU | Endpoint |
| --- | --- | ---: | ---: | --- |
| `candidate_baseline` | candidate IP | 1.0 | 0.5 | primary 20 MB |
| `candidate_relaxed` | candidate IP | 2.0 | 1.0 | primary 20 MB |
| `profile_relaxed` | encrypted profile's original address | 2.0 | 1.0 | primary 20 MB |
| `candidate_alt` | candidate IP | 2.0 | 1.0 | alternate 20 MB |

Interpretation:

- relaxed materially faster than baseline: local CPU quota contributes
- profile materially faster than candidate: forced preferred IP is harmful
- alternate materially faster than primary: download endpoint bias contributes
- all scenarios remain near 4.3 MB/s: upstream tunnel/provider capacity is the
  leading explanation, and further IP-range expansion should stop

## Safety and Data Handling

The manual template unit is:

```text
cfip-sidecar-diagnose@.service
```

It has no `[Install]` section and is not referenced by the timer. The encrypted
credential is loaded by systemd only for the oneshot run. Generated Xray JSON
remains below `/run/cfip-sidecar` and cleanup removes it and every transient
container on normal exit, error, or signal.

Diagnostic reports are stored under:

```text
/var/lib/cfip-sidecar/diagnostics/
```

They contain scenario labels, CPU limits, byte counts, HTTP status, and speed.
They do not contain the original profile address, profile body, account data,
credentials, or profile hash.

## Production Gate

This phase does not alter candidate eligibility. A Sidecar result remains
observation-only. Stable-pool or `auto` eligibility still requires the real
PassWall-path gate of at least 6.5 MB/s.

No Phase 2 diagnostic had been run when this design record was created. A
production result must be appended only after a quiet-window run and a full
post-run health check.

## Implementation Status

The manual diagnostic capability was deployed on `192.168.1.110` without
starting the diagnostic or changing the nightly observation schedule.

Validation completed at three layers:

- local Sidecar tests: passed (6 renderer tests plus installer and diagnostic
  contract tests)
- main project regression suite: passed (24 behavior groups)
- OpenClaw and Sidecar-host staging tests: passed
- local, OpenClaw-staged, Sidecar-staged, and installed file hashes: matched
- systemd unit verification: passed

The first installation attempt reached the post-install check but used an
invalid `systemctl show` query for an uninstantiated template. Its automatic
rollback completed successfully. The rollback audit confirmed the original
script hashes, active/enabled timer, inactive/successful observation service,
unchanged Docker PID, free lock, zero `cfip-direct` attachments, and no Xray
runtime config. No service was started during that attempt.

The corrected installation then passed. Production state after deployment:

```text
cfip-sidecar.timer: active/enabled
cfip-sidecar.service: inactive, last Result=success
cfip-sidecar-diagnose@.service: static and inactive
Docker PID: unchanged
existing containers: 4/4 running and healthy
cfip-direct attachments: 0
runtime Xray JSON: 0
diagnostic reports: 0
Ollama resident models: 0
Sidecar-host YouTube/Google checks: HTTP 204/204
```

The router DNS views at `192.168.1.1` and `192.168.1.254` matched the public
`1.1.1.1` result for `auto` through `auto4`. Cloudflare API was not called.
The PC browser loaded the normal YouTube and Google pages. Their synthetic
`generate_204` URL was blocked by a client-side rule and was not treated as a
network outage.

Deployment rollback point:

```text
/var/backups/cfip-sidecar/phase2-diagnose-20260717-035016
```

The planned quiet-window reference candidate is `104.17.146.147`, selected
from the third-night report because its two Sidecar rounds both produced a
minimum of 4.46 MB/s. Selection used only report columns 1-10 and 12; the
profile-hash column was neither read nor recorded.

## Production Diagnostic Result - 2026-07-20

The first controlled start at 07:27 CST failed before any network test or
transient Xray container was created. The common directory initializer tried
to chmod `/var/lib/cfip-sidecar-export`, while the manual diagnostic unit
correctly kept that observe-only path outside its `ReadWritePaths` sandbox.
The failure left the lock free, zero runtime JSON files, zero transient
containers, Docker PID 997 unchanged, and all existing containers healthy.

The least-privilege repair was committed as `ffb2c98`:

- common run and report directories remain prepared by every command
- the candidate export directory is prepared only by `export_candidates`
- the diagnostic unit was not granted any additional write path
- a dynamic regression proves common preparation succeeds when the export
  path is structurally inaccessible
- time-dependent router canary fixtures now use the current observation time,
  and the canary-plan mock executables are explicitly executable

The Sidecar and full project regression suites passed on both OpenClaw and
`192.168.1.110`. Only the Sidecar script was deployed; no unit was reloaded and
no service was stopped or restarted. Deployment details:

```text
installed SHA256: 7ea01c56546e34c77f3dc07f9262b8fc7acca1884c520ef6b44de89020872b7f
rollback: /var/backups/cfip-sidecar/write-scope-fix-20260719-235508
```

The repaired diagnostic ran from 07:56:27 to 07:57:38 CST. Its report contains
exactly four complete HTTP 200 scenarios:

| Scenario | Round 1 | Round 2 | Minimum | Average | Status |
| --- | ---: | ---: | ---: | ---: | --- |
| `candidate_baseline` | 4.10 | 4.55 | 4.10 | 4.32 | low |
| `candidate_relaxed` | 4.48 | 3.67 | 3.67 | 4.08 | low |
| `profile_relaxed` | 2.12 | 1.48 | 1.48 | 1.80 | low |
| `candidate_alt` | 3.77 | 4.48 | 3.77 | 4.12 | low |

Effect estimates from this serial run:

- CPU effect: relaxed average was 5.6% lower and minimum was 10.5% lower than
  baseline; more local CPU did not improve throughput.
- Target-address effect: the original profile address was 55.9% lower by
  average and 59.7% lower by minimum than the forced candidate address.
- Endpoint effect: the alternate endpoint was only 1.0% higher by average and
  2.7% higher by minimum; this is not a material endpoint bias.

All scenarios remained below 6.5 MB/s. No candidate was exported or promoted,
and no DNS, Cloudflare, pool, PassWall, firewall, route, subscription, token,
or credential change was attempted. Post-run checks passed for PassWall
processes/listeners, five three-view DNS records, PC/OpenClaw/router/Sidecar
HTTP, Docker, Ollama, locks, and transient cleanup. Cloudflare API was not
rechecked.

The current decision is to keep the existing CPU limits, primary endpoint, and
candidate-address override. Because the target-address difference is large
but the scenarios were serial, repeat the same bounded diagnostic on one more
quiet night before declaring the upstream profile/server/ISP path the final
bottleneck. Do not expand the normal IP scan or lower the 6.5 MB/s gate.
