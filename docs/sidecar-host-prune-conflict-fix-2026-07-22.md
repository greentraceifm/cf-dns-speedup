# Sidecar Host-Prune Conflict Fix - 2026-07-22

## Incident

The natural Sidecar observation at 03:34:59 CST on 2026-07-22 exited before
creating an Xray config, container, or download. Its first failing gate was:

```text
sidecar ipvlan network is missing or invalid
```

The failure was safe, but both persistent runtime prerequisites were gone:

- Docker network `cfip-direct`
- tagged image `cfip-sidecar-runtime:20260714`

PassWall, DNS, Docker, Ollama, and the four existing application containers
were not stopped or restarted by the failed run.

## Root Cause

This was a deterministic cross-project cleanup conflict, not a Sidecar cleanup
bug or a Docker restart.

Timeline in CST:

1. At 23:29-23:30 on 2026-07-21, the second-night diagnostic successfully used
   `cfip-direct`, proving that the network still existed.
2. At 03:26:08 on 2026-07-22, `sub2api-auto-cleanup.timer` ran its daily job.
3. The cleanup log explicitly recorded `Deleted Networks: cfip-direct` and
   deletion of image ID
   `sha256:14f117f1711d94f474db5fc40dddd7e4d279121d4f4a541e6af0dd9be85ebd8d`.
4. At 03:34:59, the Sidecar timer reached its network gate and failed closed.

The cleanup script used:

```text
docker system prune -af --filter 'until=168h'
```

The host runs multiple independent Docker projects. Sidecar's network and
tagged runtime image are intentionally unattached between nightly jobs, so
Docker classifies them as unused. Once they became older than seven days, the
global prune made them eligible immediately before the Sidecar timer.

Docker PID 997 had remained running since 2026-07-15. Repository and deployed
Sidecar cleanup code contained no Docker network or image removal. Shell
history, scheduled-unit, and journal review found no competing manual removal.

## Policy Repair

The Sub2API cleanup policy was narrowed for a multi-project host:

- retain the seven-day threshold
- prune old stopped containers
- prune only old dangling images, not all unused tagged images
- do not perform global network pruning
- retain the existing bounded BuildKit-cache cleanup
- inventory all current networks and tagged images before cleanup and fail if
  any of those resources disappears during the job

The reviewed source is versioned at:

```text
sidecar/integration/sub2api-auto-cleanup.sh
```

Production deployment:

```text
SHA256: 8dc3ba949f54b520aa3729ca0e5b7362c4d654eeea997bb1d1c5f86e1aed3737
target: /usr/local/sbin/sub2api-auto-cleanup.sh
rollback: /var/backups/cfip-sidecar/cleanup-conflict-20260722-000823
```

The service and timer units, cleanup schedule, Docker daemon, and all running
containers were left unchanged.

## Resource Restoration

`cfip-direct` was recreated through the existing `network-ensure` command and
validated with the original contract:

```text
driver=ipvlan
parent=ens160
ipvlan_mode=l2
subnet=192.168.1.0/24
gateway=192.168.1.254
attachments=0
network_id=5e7a085a33e7819668c427aaf3ca0e2d1062dd52c4328613baeb4086cbce600e
```

The deleted runtime image was rebuilt locally from the previously deployed,
hash-verified assets. The build used `FROM scratch`, `--network=none`, and
`--pull=false`; no remote image was fetched.

```text
image_id=sha256:e3e94d07c94c3cc9119542bd543966e6805c6768195075401a1481941c646208
size=25,459,689 bytes
```

Docker PID remained 997 and the four existing containers remained healthy.

## Verification

- The host-cleanup policy regression passed.
- All Sidecar tests passed.
- All project regression groups passed.
- `git diff --check` passed.
- Sidecar preflight passed before and after a production safe-prune canary.
- The canary reclaimed 0 B and preserved the exact network and image IDs.
- A low-traffic `path-check` passed and proved distinct host and Sidecar exits.
  Its first host TLS attempt timed out; the existing bounded retry succeeded.
- No transient container, network attachment, lock, or runtime Xray JSON
  remained.
- The historical failed unit state was reset without starting the service;
  Sidecar is inactive/success and its timer remains active/enabled.
- PassWall stayed enabled with two Xray processes and listeners 1070, 1041,
  11400, and 15353.
- PC, OpenClaw, router, and Sidecar Google/YouTube checks returned HTTP 204.
- All five `auto` records matched across LAN DNS, router DNS, and `1.1.1.1`.
- Cloudflare API was not rechecked.

No manual observation, candidate scan, DNS update, pool promotion, PassWall
restart, or service cutover was performed. The next natural cleanup and
Sidecar timer cycle remains the final runtime confirmation of the schedule
interaction.
