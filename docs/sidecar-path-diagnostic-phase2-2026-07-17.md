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

## Replication Diagnostic Result - 2026-07-21

The next natural observation completed successfully before the replication
attempt. Its five candidates all returned HTTP 200, with Sidecar minima from
4.23 to 5.17 MB/s. None reached the unchanged 6.5 MB/s production gate.

The first review found one Ollama model resident, so the hard gate stopped the
diagnostic before it was started. No model or service was stopped. After the
model unloaded naturally, every pre-run gate was repeated and passed: load was
0.09, Docker PID remained 997, all four existing containers were healthy, the
Sidecar lock was free, there were no runtime Xray JSON files or transient
containers, and `cfip-direct` had zero attachments. PassWall had two Xray
processes and listeners 1070, 1041, 11400, and 15353. PC, OpenClaw, router, and
Sidecar HTTP probes returned 204, and all five records matched across
`192.168.1.1`, `192.168.1.254`, and `1.1.1.1`. Cloudflare API was not rechecked.

The single authorized replication ran from 23:29:21 to 23:30:25 CST. Report:

```text
/var/lib/cfip-sidecar/diagnostics/sidecar-diagnostic-20260721-152933.tsv
```

It contains exactly four complete scenarios, each with two successful rounds:

| Scenario | Round 1 | Round 2 | Minimum | Average | HTTP | Bytes per round | Status |
| --- | ---: | ---: | ---: | ---: | --- | ---: | --- |
| `candidate_baseline` | 3.72 | 4.04 | 3.72 | 3.88 | 200/200 | 20,971,520 | low |
| `candidate_relaxed` | 4.24 | 4.14 | 4.14 | 4.19 | 200/200 | 20,971,520 | low |
| `profile_relaxed` | 1.98 | 4.20 | 1.98 | 3.09 | 200/200 | 20,971,520 | low |
| `candidate_alt` | 3.93 | 3.61 | 3.61 | 3.77 | 200/200 | 20,000,000 | low |

Replication effects, using the predeclared average-speed criteria:

- CPU effect: `candidate_relaxed` was 8.0% above baseline, within the 20%
  no-material-effect band. Extra CPU again did not explain the limit.
- Target-address effect: `profile_relaxed` averaged 73.7% of
  `candidate_relaxed`, just outside the replication requirement of at most
  70%. The strict average criterion therefore did not reproduce. Its minimum
  was still 52.2% lower, showing a large but temporally unstable target-path
  penalty.
- Endpoint effect: `candidate_alt` averaged 10.0% below
  `candidate_relaxed`, within the 20% no-material-effect band. Endpoint choice
  again did not explain the limit.

All scenarios remained below 6.5 MB/s. The run did not scan IP ranges, export
or promote a candidate, update DNS or Cloudflare, change a pool, or stop,
restart, switch, or reconfigure PassWall. Post-run checks again passed for the
Sidecar unit and timer, locks and transient cleanup, Docker PID and container
health, Ollama idle state, PassWall processes and listeners, four-host HTTP,
and five-record three-view DNS consistency.

## Phase 2 Closeout Decision

The second night confirms that increasing local CPU and changing the download
endpoint are not useful optimization directions. It does not strictly confirm
the first night's target-address effect because one profile round recovered to
4.20 MB/s and raised the average above the 70% replication cutoff. The target
address remains a plausible variable, but its effect is not stable enough to
justify a production policy change.

Keep the current CPU limits, primary endpoint, candidate override, normal scan
size, and real PassWall 6.5 MB/s gate. Do not promote any observed candidate
and do not expand Cloudflare IP discovery. The persistent sub-6.5 MB/s tunnel
envelope makes the upstream profile, server capacity, or ISP tunnel path the
leading next investigation area, but that requires a separately reviewed
profile or node-capacity experiment. It is outside this diagnostic phase and
must not modify subscriptions or credentials automatically.

Closeout repository verification passed on OpenClaw: all Sidecar tests and all
full-project regression groups passed, and the documentation patch passed
`git diff --check`. The test staging directory and archive were removed.
