# CFIP Sidecar Xray Residue Guard - 2026-07-19

Marker: `CFIP-SIDECAR-XRAY-RESIDUE-GUARD-20260719`

## Finding

The Sidecar exit handler previously deleted every regular file matching
`/run/cfip-sidecar/xray-*.json`. That behavior could erase evidence from an
unknown Xray process or another interrupted task and could allow a later run to
continue without explaining the residue. The check also ignored non-regular
paths such as a directory or symbolic link with the same name pattern.

## Fix

- Track only Xray configuration paths created by the current process.
- Register a configuration path before rendering, so a partial render is still
  removed by the current process cleanup handler.
- Delete only registered paths during cleanup.
- Fail closed when any pre-existing `xray-*.json` path is present in the
  Sidecar run directory, regardless of file type.
- Add regression coverage for tracked cleanup, unknown residue preservation,
  non-file residue rejection, and partial-render cleanup.

No PassWall, DNS, Cloudflare, pool, firewall, route, timer, credential, or
container configuration behavior was changed.

## Review

The IT expert council routing selected the read-only OpenClaw security and SRE
review lenses. The action gate classified the deployment as low risk only with
these conditions: test first, verify current ownership and lock state, create a
root-only rollback point, replace only the Sidecar script atomically, do not
start a scan, and do not restart Sidecar, Docker, Ollama, PassWall, or DNS.

The main residual risk is runtime behavior during the next natural timer run.
The patch therefore remains behind the existing post-timer read-only gate.

## Verification

- Sidecar test suite passed, including the new residue guard regression.
- Full project regression suite passed.
- Staged and installed Bash syntax checks passed.
- Installed script SHA256:
  `5b62e5d89487ff0a520c23a2296ec97ae2c1fea2fa4c7ae8d43ed339ebfcb763`.
- The pre-change installed hash was
  `68fff6bf34d61ac924006e12083223963a6ecd250ba84a66d3e4689d3e0c2a71`,
  which exactly matches repository commit `0c143e9`. The older
  `624f8bc9...` value in the retry deployment record belongs to commit
  `7771d5b`; the difference was a stale baseline, not production drift.
- `cfip-sidecar.service` had no running process (`MainPID=0`). Its `failed`
  ActiveState is the preserved historical public-IP probe timeout.
- `cfip-sidecar.timer` remained active and enabled; no manual run was started.
- Sidecar lock was free, no Xray JSON residue existed, and `cfip-direct` had no
  attached container.
- Docker PID remained `997`; all four existing containers remained healthy;
  Ollama had no resident model.
- PC, OpenClaw, Sidecar, and router Google/YouTube checks returned HTTP 204.
- `auto` through `auto4` matched across LAN DNS, router DNS, and `1.1.1.1`.
- PassWall remained enabled with two Xray processes, Xray `26.6.27`, and the
  expected listeners `1070`, `1041`, `11400`, and `15353`.
- The target PassWall init script does not implement a useful `status` action;
  it prints usage with exit code 0. Runtime health must use process, listener,
  HTTP, and topology evidence instead of parsing that output.
- Cloudflare API was not rechecked.

## Deployment And Rollback

The script was atomically replaced on `192.168.1.110` without starting or
restarting any service. The root-only rollback point is:

    /var/backups/cfip-sidecar/residue-guard-20260719-005109

Its SHA256 manifest was verified before replacement. Rollback restores only
`/opt/cfip-sidecar/cfip-sidecar.sh` and does not require a PassWall or network
service restart.

## Remaining Runtime Gate

The next natural Sidecar observation is expected at approximately 03:33 CST.
The existing 04:40 supervisor must confirm a new successful report, free lock,
no residual Xray path or container, unchanged Docker/PassWall health, HTTP 204,
and three-view DNS consistency. Candidates remain ineligible for stable or
`auto` control unless they pass the existing real PassWall `6.5 MB/s` gate.
