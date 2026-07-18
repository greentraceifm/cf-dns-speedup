# CFIP Phase 3: No-Outage Candidate Gate

Date: 2026-07-18

## Scope

This change separates candidate discovery from production PassWall and DNS
changes. It addresses the recurring 06:30 outage caused by the old job stopping
or restarting the active proxy.

The existing production baseline remains authoritative:

- The unattended 06:30 and 15:30 proxy-stopping jobs are disabled.
- `CFST_ALLOW_PROXY_STOP=0` remains the default and is enforced fail-closed.
- The current real PassWall sample is below 6.5 MB/s and no real qualified
  candidate exists.
- The Sidecar has not produced a candidate at or above the 6.5 MB/s gate.
- No Cloudflare DNS record, stable pool, champion pool, or PassWall runtime is
  changed by this phase.

## Candidate Flow

1. Sidecar observes through its independent ipvlan address.
2. `sidecar/export-candidates.py` parses the private observation TSV and
   atomically writes only qualified rows to
   `/var/lib/cfip-sidecar-export/candidates.latest.tsv`.
3. The export contains no profile hash, profile body, credentials, or node
   identity. A run with no qualified candidate produces a header-only file.
4. `router-candidate-gate.sh import FILE` validates the schema, timestamp,
   Cloudflare IPv4 range, HTTP status, speed arithmetic, duplicate IPs, file
   size, and the hard 6.5 MB/s floor. It writes only the router staging queue.
5. `router-candidate-gate.sh canary-plan` renders a temporary Xray config and
   runs `xray run -test`. It does not start Xray or touch PassWall.
6. `router-candidate-gate.sh canary IP` starts one private loopback Xray
   process using the current PassWall runtime settings, runs two serial 20 MB
   HTTPS rounds at low priority, and terminates only its own PID.
7. The canary must leave the existing Xray PID set, listeners, PassWall UCI
   file, runtime JSON, and staging hash unchanged. A mismatch is a hard stop.
8. A competition candidate requires three distinct passing calendar days and
   three distinct Sidecar export epochs within the qualification window.

The isolated router canary is deliberately named `router_isolated_xray`. It is
not reported as a real PassWall process result. A candidate still needs the
existing real PassWall path gate before it can enter stable or control `auto`.

## Production Safety

- No new timer or cron entry invokes the router canary.
- No command in the new gate calls `passwall restart`, `passwall stop`, DNS
  update code, UCI mutation, or Cloudflare API.
- Temporary Xray JSON and logs are mode 600 in a mode 700 directory and are
  removed after the child is reaped. A stale directory causes a fail-closed
  stop rather than automatic deletion.
- The router import path is compatible with the target BusyBox environment; it
  uses `tail`, `tr`, and `wc` for the final-newline check and does not require
  the optional `od` utility.
- A project lock or an existing stale canary directory blocks execution.
- The Sidecar export is sanitized before its directory is made readable; the
  private observation directory remains mode 700.

## DNS Promotion Boundary

This phase does not update `auto`. The only acceptable future promotion order
is:

1. A recent Sidecar export passes the router competition gate.
2. The same IP passes the existing real PassWall path gate at 6.5 MB/s or
   higher for the required recent observations.
3. A dry-run DNS plan, backup, and independent health checks succeed.
4. A single bounded Cloudflare record transaction is applied, followed by DNS
   convergence and HTTP checks.
5. Failure rolls the record back to the last known-good value; PassWall is not
   restarted as part of the transaction.

Until steps 1 and 2 have evidence, the correct action is to leave `auto`
unchanged, even when direct or Sidecar speed is high.

## Rollback Points

- Code rollback: revert the phase commit and reinstall the previous scripts.
- Sidecar rollback: remove the exporter file and its additional
  `ReadWritePaths`/tmpfiles entry, then reload systemd in a maintenance window;
  the existing Sidecar observation report is otherwise unchanged.
- Router rollback: remove `router-candidate-gate.sh` and the staging directory.
  No PassWall, DNS, firewall, route, subscription, or token rollback is
  required because this phase does not modify them.
- Candidate rollback: delete only the staging queue and competition report.

## Verification

The repository test entry point is:

```sh
bash tests/run-all-regression-tests.sh
```

It includes legacy CFIP gates, Sidecar tests, staging tests, a no-network
canary-plan test, and a fully mocked own-PID canary test.

## Current Conclusion

The no-outage discovery and isolated validation path is ready for staged
deployment after expert review. The project is not yet at the final DNS
promotion state because the measured real PassWall candidate set is empty.
That is an evidence gate, not a software failure.

## Production Deployment Closeout

Deployment completed on 2026-07-18 at approximately 23:45 CST from GitHub
`main` commit `1b97368`.

Router staging gate:

- Installed `/root/cf-dns-speedup/router-candidate-gate.sh` with SHA256
  `dc905a815047767dde9ff53791550f10e799b934b189343dbe53f61bc24c94e0`.
- Backup: `/root/openwrt-backup/cfip-phase3-router-gate-1b97368.idcaPJ`.
- The initial staging queue contains only the schema header (one line).
- Target BusyBox dry-runs caught and fixed an optional `od` dependency and a
  Windows CRLF packaging error before production installation.
- A strict post-check rollback was exercised at
  `/root/openwrt-backup/cfip-phase3-router-gate-1b97368.AgLpOp`; it preserved
  the original PassWall state. The final deployment then passed every gate.

Sidecar exporter:

- Installed the six-file export implementation and its systemd/tmpfiles
  mappings on `192.168.1.110`.
- Backup: `/var/backups/cfip-sidecar/phase3-candidate-export-1b97368.qu6AXl`.
- A first attempt rolled back safely at
  `/var/backups/cfip-sidecar/phase3-candidate-export-1b97368.5uUcFl` because an
  exact randomized timer timestamp was treated as immutable. Final acceptance
  verifies the documented 03:30-03:36 timer window instead.
- The service was not started. Its previous start timestamp remains
  `2026-07-17 19:32:59 UTC`, and the next natural timer is approximately
  `2026-07-19 03:33 Asia/Shanghai`.
- The real `/etc/cfip-sidecar/sidecar.env` hash remained unchanged. The new
  export directory is empty, root-owned, and mode 0755; the private observation
  directory remains mode 0700.

Post-deployment verification:

- PassWall Xray PIDs remained `18923 18010`; ports 1070, 1041, 11400, and
  15353 remained listening.
- PassWall UCI and runtime JSON hashes remained unchanged.
- Docker PID remained 997; all four existing containers stayed healthy;
  `cfip-direct` had zero attached containers; Ollama had no resident model.
- PC, OpenClaw, router, and Sidecar Google/YouTube probes returned HTTP 204.
- `auto` through `auto4` matched across `192.168.1.1`, `192.168.1.254`, and
  `1.1.1.1`. Cloudflare API was not rechecked.
- No canary, PassWall restart/stop, DNS update, pool promotion, firewall,
  route, subscription, credential, cron, or timer topology change occurred.

The next gate is the first natural Sidecar run with the deployed exporter. A
header-only export keeps the router queue empty. Any exported row must still
pass three distinct isolated-router canary days and the existing real PassWall
path threshold of 6.5 MB/s before a DNS promotion can be considered.
