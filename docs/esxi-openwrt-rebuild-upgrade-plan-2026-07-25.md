# ESXi and OpenWrt rebuild plan - 2026-07-25

## Decision

Rebuild `192.168.1.254` as a clean parallel OpenWrt VM on the existing ESXi
6.7 host before considering any ESXi host upgrade. Do not rebuild
`192.168.1.110`. Do not install Proxmox. ESXi 8 validation on the empty
Samsung T5 is a separate, optional second phase and must not begin until the
new OpenWrt VM has passed its observation period.

This order addresses the current package provenance problem without combining
it with a hypervisor migration. The existing Kwrt system is operational, but
its package feed does not provide a signed index or the exact provenance-
verified rollback IPK required by the Xray-only upgrade policy. A clean image
with one internally consistent, signed package ecosystem is safer than forcing
an in-place package-manager or feed transition.

## Verified baseline

Read-only checks after the 2026-07-25 memory adjustment established:

- ESXi host `192.168.1.238`: VMware ESXi 6.7 U3 build `20497097`, standalone
  Host Client, Intel i7-7500U with 2 cores, and `32,686 MB` physical memory.
- Current host memory use was approximately `4,639 MB`, leaving an estimated
  `28,047 MB` available. No running VM showed ballooning, swapping, or
  compressed memory.
- `Ubuntu-Ollama` (`192.168.1.110`) is now configured with `16,384 MB`. The
  guest reported `15,993 MB` total and approximately `15,228 MB` available,
  with zero swap use and low load after reboot.
- Docker/containerd, PostgreSQL, Redis, Sub2API, Node, Ollama, and the Sidecar
  timer returned after the `.110` reboot. Ollama had no resident model;
  Sidecar was enabled and waiting for its next natural run; Google and YouTube
  checks returned HTTP 204.
- `Openwrt_Jump63` (`192.168.1.254`) has 1 vCPU, 1 GiB RAM, one vNIC on
  `VM Network`, and two existing snapshots. The snapshots are not backups and
  must not be deleted or consolidated during this project.
- `Ros` is the physical WAN/LAN routing VM. `192.168.1.140` is only a
  management jump host. Scheduled CFIP and proxy operation do not depend on
  `.140` being powered on.
- The Intel 800 GB SSD contains the current ESXi boot partitions and datastore,
  has about 665 GB free, reports healthy SMART status, and has media wear
  indicator `72`.
- The Samsung T5 1 TB is healthy, unpartitioned, and confirmed empty. It is a
  candidate test boot device only. The Intel SSD remains the production and
  default boot device.
- Six Intel I211 NICs use the ESXi `igbn` driver. `vmnic0` had two brief link
  flaps on 2026-07-24; `vmnic1` negotiated only 10 Mbps. These are pre-existing
  hardware/path findings and must not be attributed to the rebuild.
- ESXi SSH and Shell are always enabled, NTP is configured but inactive, there
  is no TPM/IPMI, image acceptance is `CommunitySupported`, and `upsmon` is the
  only community VIB. Physical presence is therefore required for any cold
  boot experiment.

The ESXi root credential previously appeared in a screenshot. It is not stored
in this repository or plan. The user's decision not to rotate it does not
block the rebuild, but remains a security risk to address separately.

## Non-negotiable boundaries

- Preserve the current `.254` VM, virtual disk, snapshots, MAC information,
  and Intel datastore until the full rollback period is closed.
- Do not replace `/etc` wholesale. Migrate only inventoried configuration
  objects into a matching target schema.
- Do not change Cloudflare `auto` through `auto4`, candidate/champion/stable
  pools, the real PassWall `>= 6.5 MB/s` gate, Sidecar policy, subscriptions,
  credentials, firewall intent, or routing intent.
- Do not re-enable historical proxy-stopping CFIP jobs. Sidecar remains the
  no-outage discovery/competition path.
- Never run the old and new VM with the same IP or MAC on the same port group.
- Do not upgrade VM hardware compatibility, VMFS, virtual disks, or snapshots
  during the rollback period.
- Keep the Intel SSD first in persistent BIOS boot order. ESXi 8 on T5, if
  tested, is selected only from the one-time boot menu.

## Phase 0: evidence and recovery preparation

Complete this phase before creating or changing a VM:

1. Print or locally retain the manual rollback runbook in this repository.
2. Record the old `.254` VM inventory name/ID, datastore VMX path, disk path,
   current vNIC MAC, port group, firmware mode, CPU/RAM, and autostart order.
3. Export an ESXi host configuration backup using a method valid for the exact
   6.7 build. Verify the archive is non-empty and readable off the host.
4. Create an independent cold copy/export of the `.254` VM while it is cleanly
   powered off in a planned window. Do not call its snapshots a backup.
5. From OpenWrt, record package versions, UCI section names and relationships,
   interfaces, routes, firewall zones, DHCP/DNS/SmartDNS behavior, PassWall
   global node, ACLs, listeners, cron state, CFIP file inventory, ownership,
   modes, and hashes. Keep secrets only in a protected local backup.
6. Verify the existing `.254` can be powered on from the ESXi console and that
   a direct LAN client can reach `https://192.168.1.238` without PassWall.
7. Choose a temporary management IP only after checking the DHCP pool, static
   reservations, router tables, ARP/neighbour tables, and live ICMP/ARP use.
   Record the chosen IP in the rollback runbook. Do not assume `.253` is free.
8. Photograph or write down the physical NIC/cable mapping and label the Intel
   SSD and Samsung T5 before any host-level work.

Stop if the host backup, cold VM backup, direct ESXi management path, old VM
boot test, or a conflict-free temporary IP cannot be independently verified.

## Phase 1: clean parallel `.254` rebuild on ESXi 6.7

### 1. Select a coherent target

Use a maintained x86-64 OpenWrt-derived image whose base OS, package manager,
PassWall application, Xray core, and package feeds are intended to work
together. Record image URL, release/version, architecture, published digest,
signing key/source, package repository URLs, and support lifecycle.

Reject the target if any of these are unclear, if it requires mixing APK and
OPKG artifacts, if the image requires an unsigned third-party feed for the
production proxy path, or if the exact install and rollback artifacts cannot
be retained locally.

### 2. Build without an address conflict

Create a new VM with conservative hardware compatible with ESXi 6.7. Initially
leave its production vNIC disconnected or attach it to an isolated staging
port group. Install and verify the image through the ESXi console.

When ready for LAN testing, use a unique VMware MAC and the previously verified
temporary IP. Keep the old VM at `.254`. Confirm from two LAN devices that the
temporary address and `.254` resolve to different MACs. Any duplicate-address
warning, ARP movement, or unexpected DHCP lease is a hard stop.

### 3. Migrate semantically

Recreate configuration through the target release's supported UCI/package
interfaces. Migrate only reviewed objects:

- the single-interface management/network intent and required static routes;
- dnsmasq/SmartDNS behavior and local records;
- firewall zones/rules required by the current topology;
- PassWall node and ACL semantics, TLS/WS settings, and listener topology;
- CFIP scripts, systemd/cron equivalents, state files, pools, permissions, and
  explicit no-proxy-stop safety controls;
- only the credentials required by those objects, transferred through a
  protected local channel and never committed or logged.

Do not import old init scripts, package database, feed configuration, binaries,
generated runtime JSON, `/tmp`, logs, or the complete old `/etc` tree.

### 4. Test on the temporary address

All of the following must pass before cutover:

- clean boot and repeat boot; correct clock; adequate storage and inodes;
- signed package metadata and internally consistent installed versions;
- DNS resolution and DNS-policy behavior without advertising the new VM as
  production DNS;
- PassWall configuration validation, two expected Xray instances, and required
  listeners `1070`, `1041`, `11400`, and `15353` on the intended interfaces;
- global node and ACL behavior using explicitly selected test clients only;
- Google/YouTube HTTP checks and a real proxy-path throughput baseline;
- CFIP report-only/observation commands in dry-run or read-only mode;
- no PassWall stop/restart from any scheduled CFIP path;
- no write to Cloudflare DNS or any production pool during testing;
- a reboot test showing services, listeners, permissions, and timers recover.

### 5. Minimal cutover

Schedule a staffed low-traffic window. Open the ESXi console for both VMs and
keep a direct LAN management session to `.238`.

1. Confirm all preflight checks and backups again; pause unrelated maintenance.
2. Cleanly power off the old `.254` VM. Do not delete it or detach its disk.
3. Confirm `.254` no longer answers and its MAC ages out/clears from LAN ARP.
4. Change the new VM from the temporary IP to `.254`, using the already tested
   production network configuration. Keep its unique MAC unless a documented
   dependency requires the old MAC.
5. Start/activate the new network and validate gateway, DNS, Xray processes,
   all four listeners, proxy HTTP, ACL behavior, and `auto..auto4` views.
6. Record the last successful old-path probe and first successful new-path
   probe. Existing TCP sessions may reconnect; strict zero-session-loss is not
   technically guaranteed.

Rollback immediately on management loss, DNS failure, listener loss, ACL
misrouting, repeated proxy failure, unexplained route/firewall drift, or a
material throughput collapse. Do not troubleshoot production in place beyond
the short pre-agreed cutover budget.

### 6. Observation and closeout

Keep the old VM powered off but intact. Do not upgrade its virtual hardware or
consolidate snapshots. Observe at least three natural Sidecar cycles and the
normal OpenWrt/PassWall observation windows. Confirm no proxy-stopping job,
DNS drift, residue, lock conflict, or automatic promotion bypass occurs.

Close Phase 1 only after configuration exports, package artifacts, checksums,
the final migration map, and measured interruption are stored without secrets.
Only then may the old VM be archived according to a separately approved
retention decision.

## Phase 2: optional ESXi 8 cold validation on Samsung T5

This phase does not improve CFIP speed by itself. Its purpose is to determine
whether a supported-enough hypervisor can replace the out-of-support ESXi 6.7
host without risking the Intel production installation. It requires physical
presence and a separate maintenance window with accepted outage.

1. Reconfirm the T5 identity, serial/capacity, empty status, SMART/health, and
   cable stability. Reconfirm the Intel SSD identity separately.
2. Retain the ESXi 6.7 host configuration backup and independent VM backups.
3. Install ESXi 8 only to the Samsung T5. Verify the target device by model,
   capacity, and identifier at the installer screen. If the installer cannot
   distinguish it unambiguously from the Intel SSD, stop. Physically
   disconnecting the Intel device during installation is preferred when safe
   and practical.
4. Keep Intel first in persistent boot order. Use the firmware one-time boot
   menu to select the T5 for each experiment.
5. First boot ESXi 8 without registering or powering on production VMs. Check
   CPU acceptance, USB boot persistence, management networking, all six I211
   NICs, VLAN/port groups, datastore visibility, logs, time, and repeated cold
   boots.
6. Do not import `upsmon` or other community VIBs until native host stability
   is proven. Do not upgrade VMFS or any VM hardware compatibility.
7. If host-only checks pass, create a disposable test VM on T5 and verify each
   required network path. A later, separately approved window may register
   copies of production VMs for controlled validation.

Stop and return to Intel ESXi 6.7 if ESXi 8 requires an unsupported CPU bypass,
misses any required I211 NIC, cannot reliably boot from T5, cannot preserve the
management path, reports storage instability, requires unreviewed community
drivers, or cannot leave the Intel datastore untouched.

## Final acceptance

The rebuild is successful only when:

- `.238`, `Ros`, new `.254`, and `.110` boot in the documented order;
- PassWall has the intended version set, two Xray processes, and all four
  listeners;
- node, ACL, TLS, DNS, firewall, route, subscription, and CFIP semantics match
  the approved migration inventory;
- Google/YouTube work from PC, `.110`, `.140` when powered on, and the router;
- `auto..auto4` match across LAN, router, and public DNS, without an
  unauthorized Cloudflare write;
- Sidecar/Docker/Ollama are healthy and all project locks/residue checks pass;
- three natural Sidecar/PassWall observation windows complete without outage;
- the manual rollback procedure has been dry-read by the person who will be
  physically present.

The existing PassWall Xray in-place upgrade remains deferred. The relevant
provenance findings and upgrade policy remain in
`docs/passwall-upgrade-plan-2026-07-22.md`.
