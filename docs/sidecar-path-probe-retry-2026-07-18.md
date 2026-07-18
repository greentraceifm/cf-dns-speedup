# Sidecar Public-IP Probe Retry Hardening - 2026-07-18

## Incident

The normal 03:30 Sidecar observation exited before discovery because the
isolated public-IP probe to www.cloudflare.com:443 timed out. No observation
report, DNS update, pool mutation, or PassWall action occurred.

A bounded path-check at 08:55 completed in three seconds with distinct host
and Sidecar public exits. This supports a transient endpoint/path failure
rather than a persistent bypass or ipvlan failure.

## Expert Review

The SRE and security review approved a narrow retry change with these
conditions:

- use the same HTTPS endpoint; do not add a fallback public-IP provider
- retry both the host and isolated Sidecar probe at most three times
- use a fixed three-second delay and retain the existing per-attempt timeout
- reject invalid retry settings
- continue to fail closed when probes are exhausted, return an empty value, or
  expose the same public IP
- do not start an observation, diagnostic, PassWall restart, DNS update, pool
  update, Docker restart, or service-state change as part of deployment

## Implementation

cfip-sidecar.sh now defaults to:

    SIDECAR_PATH_CHECK_ATTEMPTS=3
    SIDECAR_PATH_CHECK_RETRY_DELAY=3

The retry helper treats a failed command or empty response as a failed attempt.
After the bounded attempts are exhausted, the existing observation/diagnostic
command still aborts before any scan or Xray candidate validation starts.

The script entry point is wrapped in main so retry behavior can be sourced and
tested without executing a Sidecar command.

## Validation

Passed in the disposable mirror and again in the authoritative repository:

- Bash syntax checks
- six Xray renderer tests
- installer idempotency test
- diagnostic contract test
- retry succeeds on the third attempt
- retry stops after three failed attempts
- zero attempts and a non-numeric delay are rejected
- matching host and Sidecar exits remain fail-closed
- all 24 main CFIP regression groups

The same Sidecar test suite also passed from isolated staging directories on
OpenClaw and 192.168.1.110. Local, OpenClaw, and Sidecar staging hashes matched
for the changed script, example environment, and retry test.

## Production Status

The code is tested and staged only. It is not installed in
/opt/cfip-sidecar.

The existing OpenClaw maintenance key can still log in as the unprivileged
ollama account, but the stored legacy maintenance password was rejected by
sudo. No additional password attempts were made. The production directory and
configuration remain root-owned, so the deployment correctly stopped at the
privilege gate.

Installed production hashes still match commit a5fa067:

    cfip-sidecar.sh             8fa48932dfe77375703b49872022814e8680f6d677c482f2cbf7f089241dba49
    cfip-sidecar.env.example    93e27a9db2a9e6019ce0972d92e6f13e25ca224496bdfa8a64f730b3e35fae24

Staging path on the Sidecar host:

    /tmp/cfip-sidecar-retry-20260718/sidecar

## Deployment And Rollback Gate

After approved sudo maintenance access is restored:

1. Recheck lock, timer/service state, Docker dependencies, Ollama, connectivity,
   PassWall health, and three DNS views.
2. Back up only the installed Sidecar script and example environment under a
   new root-only /var/backups/cfip-sidecar/ directory.
3. Verify backup hashes and run the staged tests.
4. Install only cfip-sidecar.sh and cfip-sidecar.env.example; do not modify the
   real /etc/cfip-sidecar/sidecar.env.
5. Recheck installed hashes and Bash syntax. Do not run observe or diagnose
   during active use.
6. Let the next normal 03:30 timer provide the first production sample.

Rollback restores the two backed-up files. No PassWall, Docker, DNS, firewall,
route, timer, or systemd unit restart is required.
