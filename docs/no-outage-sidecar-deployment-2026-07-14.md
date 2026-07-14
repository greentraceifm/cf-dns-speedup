# No-Outage CFIP Sidecar Deployment - 2026-07-14

## Summary

An observation-only Cloudflare preferred-IP Sidecar is deployed on the Ubuntu
Docker host at `192.168.1.110`. It discovers candidates through an isolated
direct path and validates the top five through a temporary Xray process that
uses the same protocol/profile class as PassWall.

The Sidecar does not stop, restart, or switch PassWall. It does not update
Cloudflare DNS and cannot promote candidates into the champion pool.

## Isolation

- Docker network: `cfip-direct`, driver `ipvlan`, mode `L2`.
- Sidecar address: `192.168.1.252/24`.
- Parent interface: `ens160`.
- Gateway: `192.168.1.254`.
- The existing `192.168.1.110 -> auto3` PassWall ACL remains unchanged.
- The router has an exact direct-bypass ACL for only `192.168.1.252`.
- Incremental live rules were added to `PSW_DNS`, `PSW_NAT`, and
  `PSW_MANGLE`; PassWall was not reloaded or restarted.
- No container port is published. Xray listens only on loopback inside the
  transient container namespace.

The deployment canary proved that the regular host path and the Sidecar path
use different public exits. The implementation deliberately logs only the
comparison result, not the exit addresses.

## Runtime Policy

The nightly timer is enabled and runs at about `03:30 Asia/Shanghai`, with up
to five minutes of random delay. `Persistent=false` prevents a missed night
from becoming a daytime catch-up scan.

Each run must pass these gates:

- Ollama has no resident model.
- One-minute load is below `1.0`.
- Available memory is at least `4 GiB`.
- Available disk is at least `10 GiB`.
- `k12-reg`, `sub2api`, `sub2api-postgres`, and `sub2api-redis` are healthy.

Resource controls:

- At most `1 CPU` per transient workload.
- Direct-scan container memory: `512 MiB`.
- Xray container memory: `384 MiB`.
- Curl validation container memory: `128 MiB`.
- Per-container process limit: `64`.
- Low service and container CPU/IO weight.
- Systemd service memory ceiling: `768 MiB`.
- Systemd start timeout: `75 minutes`, covering a worst-case 50-to-100
  expanded scan plus ten 20 MB proxy downloads.

Discovery starts with 50 download candidates. If fewer than five reach the
direct soft floor, it retries with 100. Only the top five are proxy-validated,
serially, with two 20 MB downloads per candidate.

## Credential Handling

- The source Xray profile is stored as a systemd encrypted credential.
- The encrypted blob is mode `0600` and is not committed to Git.
- Decrypted input and generated Xray configuration exist only below `/run`
  while the oneshot service is active.
- Cleanup removes transient Xray containers and generated runtime configs.
- No credential, token, profile body, or profile hash is included in this
  deployment record.

The host has no TPM-backed or encrypted-root protection. Systemd credential
encryption reduces casual plaintext exposure but does not protect against
full-disk theft. This is an accepted residual risk for the observation-only
stage.

## Safety Boundary

A Sidecar result is not equivalent to production qualification.

1. Direct discovery only identifies potentially fast Cloudflare IPs.
2. Sidecar Xray validation confirms same-protocol behavior from the same ISP
   egress class.
3. A passing result may enter only the competitive observation queue.
4. Stable-pool or `auto` eligibility still requires the existing real
   PassWall-path gate of at least `6.5 MB/s`.

The timer and scripts contain no Cloudflare mutation or champion-pool write
path.

## Canary Evidence

The initial canary used `104.17.136.166` without running a direct scan:

```text
round1=3.53 MB/s
round2=4.27 MB/s
min=3.53 MB/s
avg=3.90 MB/s
HTTP=200/200
status=low
```

The `6.5 MB/s` Sidecar gate correctly rejected it. No DNS or pool change was
attempted.

After removing curl's unnecessary TLS certificate bypass, a direct 20 MB
certificate probe returned HTTP 200 with all `20,971,520` bytes. The Xray
canary was then repeated with normal certificate verification:

```text
round1=4.22 MB/s
round2=4.69 MB/s
min=4.22 MB/s
avg=4.46 MB/s
HTTP=200/200
status=low
```

The hardened path also behaved correctly and remained below the gate.

## Verification

Local and Ubuntu staging:

```text
Sidecar syntax/tests: passed
render-xray-config tests: 4 passed
installer idempotency test: passed
main regression suite: passed
git diff --check: passed
staged secret scan: no findings
insecure curl TLS bypass check: passed
```

Production closeout:

```text
cfip-sidecar.service: inactive/dead, Result=success
cfip-sidecar.timer: enabled and active
TimeoutStartUSec: 1h 15min
cfip-direct attached containers: 0
Docker PID: 837746 (unchanged from deployment baseline)
existing four Docker containers: healthy
runtime plaintext Xray configs: none
direct TLS certificate probe: HTTP 200, 20,971,520 bytes
TLS-verified Xray canary: HTTP 200/200, minimum 4.22 MB/s, rejected low
production preflight while Ollama busy: correctly yielded
production preflight after natural Ollama eviction: ok
YouTube generate_204 from PC and host: HTTP 204
Google generate_204 from PC and host: HTTP 204
```

Router and public DNS agreed after closeout:

```text
auto  = 104.17.136.166
auto1 = 104.17.134.190
auto2 = 104.17.136.166
auto3 = 104.17.130.225
auto4 = 104.17.156.195
```

The router was not mutated during the closeout update. Cloudflare API was not
called during this file-only closeout; the public authoritative result was
used as the second DNS view.

## Expert Review

The IT Engineering Council review conditionally approved the deployment:

- SRE: isolation, busy-yield behavior, rollback, and evidence are adequate.
- Security: no exposed port or repository credential was found; the lack of
  full-disk hardware-backed credential protection remains a documented risk.
- Engineering: keep Sidecar data observation-only until three distinct
  successful nightly samples exist.
- Strongest objection: a Sidecar pass must never bypass the real PassWall
  gate or directly control `auto`.

## Rollback

Initial deployment backups:

```text
/root/openwrt-backup/cfip-sidecar-20260714-081311
/var/backups/cfip-sidecar/deploy-20260714-000549
```

Closeout file backup:

```text
/var/backups/cfip-sidecar/closeout-20260714-0850
```

Rollback order:

1. Disable the Sidecar timer.
2. Restore `/opt/cfip-sidecar`, the systemd unit/timer, tmpfiles rule, and
   Sidecar environment from the closeout backup.
3. Reload systemd metadata; do not restart Docker or PassWall.
4. If the entire feature is retired, remove the unused `cfip-direct` network
   and the exact `192.168.1.252` router bypass in a maintenance window.

No rollback is currently required.

## Observation Gate

The heartbeat `continue-progress-openwrt-cfip-sidecar-3night` performs a
read-only review at 04:30. It will close after three successful, date-distinct
nightly reports, or stop and notify on a safety inconsistency. It is forbidden
from starting scans, updating DNS, changing pools, or restarting services.
