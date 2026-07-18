# OpenWrt CFIP Sidecar Probe Retry Deployment - 2026-07-18

Marker: CFIP-SIDECAR-PROBE-RETRY-DEPLOYED-20260718-7771D5B

Authority commit: `7771d5b`

## Deployment

The bounded public-IP path-probe retry was deployed to `192.168.1.110` at
approximately 12:09 CST. Only these two files were replaced:

    /opt/cfip-sidecar/cfip-sidecar.sh
    /opt/cfip-sidecar/cfip-sidecar.env.example

Installed hashes:

    cfip-sidecar.sh             624f8bc90f4056fd44b4930a41aa409d835043c6c6926fe5a06ba2fe66b2223e
    cfip-sidecar.env.example    69390764ceb068d3ac70a1090e5cacf537a5258f584f5b47d60a1d66a233ea0a

The real `/etc/cfip-sidecar/sidecar.env` remained unchanged. No observation or
diagnostic was started. PassWall, Docker, Ollama, DNS, firewall, routes, timers,
and systemd services were not restarted or modified.

## Verification

- staged Sidecar test suite passed, including the retry regression
- Sidecar lock remained free and the timer remained active/waiting
- Bash syntax and installed/staged hashes matched after deployment
- all four existing Docker containers remained healthy; Docker PID stayed 997
- `cfip-direct` had no attached container and `/run` had no Xray JSON residue
- Ollama had no resident model; Sidecar Google/YouTube probes returned HTTP 204
- PassWall remained enabled with two Xray processes and expected listeners
- router Google/YouTube probes returned HTTP 204
- `auto` through `auto4` matched across 192.168.1.1, 192.168.1.254, and 1.1.1.1

Cloudflare API was not rechecked. The existing failed Sidecar service result is
the historical 03:30 probe timeout; the service is inactive and no new run was
triggered during deployment.

## Rollback

Root-only rollback point:

    /var/backups/cfip-sidecar/retry-20260718-040859-1433431

Its SHA256 manifest was verified before replacement. Rollback restores only the
two installed files and does not require restarting PassWall, Docker, DNS, the
timer, or any network service.

## Runtime Gate

The next normal 03:30 timer run is the first production runtime sample. A
successful report confirms the retry on the normal path. A failed report must
remain fail-closed and must not trigger DNS changes, pool promotion, or an Xray
upgrade.
