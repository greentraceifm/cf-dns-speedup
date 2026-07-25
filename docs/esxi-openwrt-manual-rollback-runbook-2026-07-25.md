# Manual rollback runbook: ESXi/OpenWrt rebuild - 2026-07-25

## Purpose

Use this runbook when the new OpenWrt VM or the optional ESXi 8 T5 experiment
fails and automatic rollback, Codex, PassWall, or Internet access is not
available. It is intentionally independent of `.140` and external services.

Print this document before the change. Fill in every blank below by reading
the ESXi Host Client and the verified pre-change inventory. Do not write any
password, token, subscription, UUID, or node credential on this copy.

## Pre-change recovery card

```text
Date/time and operator: _________________________________________________
ESXi management URL: https://192.168.1.238
ESXi local-console management IP/VLAN: _________________________________
Old OpenWrt VM inventory name: Openwrt_Jump63
Old OpenWrt VM inventory ID: ___________________________________________
Old OpenWrt VM VMX datastore path: _____________________________________
Old OpenWrt virtual disk path: _________________________________________
Old OpenWrt vNIC MAC: __________________________________________________
Old OpenWrt port group: VM Network
Old OpenWrt firmware / vHW version: ____________________________________
New OpenWrt VM name and inventory ID: __________________________________
New OpenWrt vNIC MAC: __________________________________________________
Verified temporary management IP: ______________________________________
Temporary IP confirmed outside DHCP/static use at: _____________________
ESXi 6.7 host-config backup path and checksum: __________________________
Old OpenWrt cold backup/export path and checksum: _______________________
Protected OpenWrt config backup path: __________________________________
Intel SSD model/serial suffix: _________________________________________
Samsung T5 model/serial suffix: ________________________________________
Firmware one-time boot-menu key shown at POST: __________________________
Known-good rollback test date/result: __________________________________
```

Required physical NIC map:

| ESXi NIC | Current role / port group |
| --- | --- |
| `vmnic0` | Management Network / VM Network |
| `vmnic5` | WAN6 |
| `vmnic4` | LAN5 |
| `vmnic3` | LAN4 |
| `vmnic2` | LAN3 |
| `vmnic1` | LAN2; pre-change link observed at only 10 Mbps |

Keep a monitor and keyboard connected to `.238`, a LAN laptop with a static
fallback address, and access to the ESXi Host Client. Because `.238` has no
IPMI, do not begin ESXi cold testing without a person physically present.

## Immediate safety rules

During rollback:

- do not update Cloudflare DNS or `auto..auto4`;
- do not change candidate, champion, or stable pools;
- do not lower or bypass the real PassWall `6.5 MB/s` gate;
- do not edit firewall, routes, subscriptions, credentials, or Sidecar policy;
- do not run CFIP scans, `external-observe`, `stability-update`, or candidate
  apply actions;
- do not delete either OpenWrt VM, any datastore, snapshot, virtual disk, or
  backup;
- do not consolidate snapshots, upgrade VM hardware, or upgrade VMFS;
- do not repeatedly restart PassWall. Restore the known-good VM instead;
- never allow old and new OpenWrt VMs to use `.254` simultaneously.

If a step does not match what is visible on screen, stop and record the exact
screen/error. Do not improvise storage, datastore, or partition operations.

## Decision tree

```text
Can https://192.168.1.238 be opened from the direct LAN?
|
+-- YES -> Is ESXi 6.7 booted from the Intel SSD?
|          |
|          +-- YES -> Follow "Rollback the .254 VM".
|          |
|          +-- NO / ESXi 8 on T5 -> Follow "Return the host to Intel ESXi 6.7".
|
+-- NO -> Can the ESXi Direct Console (DCUI) be opened physically?
           |
           +-- YES -> Follow "Recover ESXi management access" first.
           |
           +-- NO -> Stop power cycling. Check display/power/cabling and
                      record LEDs and screen state before one controlled reboot.
```

## Rollback the `.254` VM

Use this procedure for any new-VM management, DNS, proxy, ACL, route,
firewall, listener, or performance acceptance failure.

1. From a direct LAN client, open `https://192.168.1.238` and sign in locally.
   Do not depend on PassWall or `.140`.
2. Open the console of the **new** OpenWrt VM and record its visible state.
3. Power off the **new** OpenWrt VM. If guest shutdown does not finish within
   the agreed short budget and the proxy is already unavailable, use ESXi
   `Power off` once. Do not delete or unregister it.
4. In the new VM settings, clear `Connect at power on` for its production vNIC
   or leave the entire new VM powered off. This prevents an IP conflict.
5. Confirm the old `Openwrt_Jump63` VM still references the recorded VMX,
   virtual disk, vNIC MAC, and `VM Network` port group. Do not alter its
   snapshots or virtual hardware.
6. Ensure the old VM vNIC is `Connected` and `Connect at power on` is selected.
7. Power on only the old `Openwrt_Jump63` VM and open its ESXi console.
8. Wait up to two minutes for normal boot. Confirm the console shows the
   expected old release and no filesystem recovery error.
9. From the LAN laptop, clear only the local stale ARP/neighbour entry for
   `192.168.1.254`, then ping `.254`. Do not flush router-wide neighbour tables.
10. Verify `.254` returns to the recorded old MAC. If a different MAC answers,
    stop: another `.254` instance is active.
11. Perform the health checks in the section below. If they pass, leave the new
    VM powered off and preserve all evidence.

Do not restore `/etc`, opkg state, or individual PassWall files if the intact
old VM boots. VM-level rollback is the primary recovery method.

## If the old `.254` VM does not boot

1. Keep the new VM powered off and disconnected.
2. Record the old VM console error and ESXi task/event message.
3. Verify the VM points to the pre-change VMX and disk paths written on the
   recovery card. Do not answer any prompt that says a disk will be created,
   formatted, upgraded, moved, or consolidated.
4. If ESXi asks whether the VM was moved or copied and this is the unchanged
   original VM, cancel and re-check that the original inventory entry and VMX
   were selected. Do not generate a new identity casually.
5. If the original inventory entry is missing but the datastore is healthy,
   use Datastore Browser to locate the exact recorded original VMX and choose
   `Register VM`. Verify the disk and MAC before power-on.
6. If the original disk is missing, inaccessible, or reports corruption, stop.
   Do not attach a similarly named disk. Restore the independently verified
   cold VM backup according to its backup product's documented procedure.
7. If no verified cold backup is available, this is an emergency requiring
   expert intervention. Do not attempt snapshot-chain surgery.

## Recover ESXi management access

Use the physical ESXi Direct Console User Interface (DCUI):

1. Read and photograph the current screen before changing anything.
2. Confirm the host is powered and that the management cable is still on the
   physical port mapped to `vmnic0`.
3. Open `Configure Management Network` and compare, without changing, the
   management adapter, VLAN, IPv4 address, subnet mask, and gateway with the
   pre-change recovery card.
4. Run `Test Management Network`. A DNS test failure alone is not proof that
   local management is broken; the critical checks are local link, gateway,
   and `192.168.1.238` reachability.
5. If the wrong NIC/VLAN/address is selected and the recorded known-good values
   are unambiguous, restore exactly those values and restart the management
   network once when DCUI asks. Do not reset the entire ESXi configuration.
6. If `vmnic0` has no link, check the known cable/switch port. Do not swap WAN
   and LAN cables by trial and error; use the physical NIC map.
7. Once Host Client access returns, determine which boot device/version is
   active, then follow the appropriate rollback section.

## Return the host to Intel ESXi 6.7

Use this procedure if ESXi 8 on Samsung T5 fails installation, boot, driver,
network, storage, or repeated cold-boot acceptance.

1. Record the ESXi 8 screen/error and whether any production VM was started.
2. Shut down the test host from DCUI if responsive. Otherwise perform one
   controlled power-off only after disk activity has stopped or the system is
   clearly hung.
3. Remove the Samsung T5 from the one-time boot choice. If Intel remains first
   in persistent BIOS order, a normal reboot should return to Intel ESXi 6.7.
4. If it does not, enter the firmware one-time boot menu using the key recorded
   on the recovery card and select the **Intel SSD identified by its recorded
   model/serial**, not a generic similarly sized entry.
5. Do not select the T5 again and do not change SATA mode, UEFI/legacy mode,
   Secure Boot, or partition settings while recovering.
6. Confirm the ESXi console reports version 6.7 U3 build `20497097` and
   management address `192.168.1.238`.
7. Open Host Client and verify the Intel datastore, port groups, vSwitches,
   physical NIC mappings, VM inventory, and autostart settings before starting
   VMs.
8. Start VMs in the recovery order below. Do not allow ESXi to upgrade VMFS,
   VM hardware, or VMware Tools as part of rollback.

If Intel is absent from the firmware boot list, stop and power down. Re-seat or
reconnect it only with power removed and only if the operator is comfortable
identifying the exact device. Do not initialize or format any disk.

## VM recovery order

Use the recorded ESXi autostart order if it was independently verified and
matches this dependency sequence. Otherwise start manually:

1. Start `Ros`; wait for its WAN/LAN interfaces and LAN gateway to stabilize.
2. Start the known-good old `Openwrt_Jump63`; verify `.254`, DNS, and PassWall.
3. Start `Ubuntu-Ollama` (`.110`); allow Docker and containers to recover.
4. Start optional management services such as `.140` last. `.140` is not a
   runtime dependency of CFIP, `.254`, or `.110`.

Do not start the new OpenWrt VM during rollback.

## Health checks after rollback

Perform in order and write down pass/fail and time:

1. `.238`: Host Client reachable locally; ESXi 6.7 expected build; Intel
   datastore present; vSwitch/port-group/NIC map unchanged; no VM ballooning,
   swapping, or unexpected storage alarm.
2. `Ros`: expected WAN/LAN links up; LAN gateway reachable; no unexplained
   interface remapping.
3. `.254`: ping and SSH/LuCI reachable; expected old release and package
   versions; dnsmasq and SmartDNS running.
4. PassWall: enabled; two `/usr/bin/xray` processes; listeners `1070`, `1041`,
   `11400`, and `15353`; no new fatal/panic/invalid/unsupported log entries.
5. DNS: `auto`, `auto1`, `auto2`, `auto3`, and `auto4` return the same values
   through LAN DNS, `.254`, and `1.1.1.1`. Do not write Cloudflare to repair a
   mismatch during rollback.
6. HTTP: Google 204 and YouTube checks succeed from the LAN PC, router, `.110`,
   and `.140` if it is on. Test the actual PassWall path, not only direct WAN.
7. `.110`: memory remains approximately 16 GiB; swap is not growing; Docker
   daemon is stable; the four established containers are running/healthy;
   Ollama responds and has no unexpected resident model.
8. Sidecar: timer is enabled/active and waiting; service is not stuck; project
   lock is free; `cfip-direct` has no attached transient container; no
   `/run/cfip-sidecar/xray-*.json` residue exists.
9. CFIP: no scan/update process or lock is active; historical proxy-stopping
   jobs remain disabled; no pool or `auto` record changed during recovery.

Cloudflare API consistency is checked only with an existing safe read-only
method. If unavailable, record `Cloudflare API not rechecked`; do not infer it
from public DNS alone.

## Emergency stop criteria

Stop further action and preserve evidence if any of these occurs:

- both OpenWrt VMs appear to own `.254` or the MAC changes back and forth;
- the Intel SSD/datastore disappears or any prompt offers initialization;
- a snapshot chain or virtual disk is missing/corrupt;
- NIC roles no longer match the recorded physical map;
- the host repeatedly reboots, loses T5/Intel storage, or loses management;
- PassWall listeners do not recover on the intact old VM;
- DNS answers differ across views after the old VM is restored;
- rollback would require changing Cloudflare, firewall, routes, subscriptions,
  credentials, pools, or the Sidecar gate;
- the operator cannot unambiguously identify the old VM, Intel SSD, port group,
  or production cable.

Record: wall-clock time, current boot device and ESXi build, powered-on VMs,
console screenshots, exact error text, ESXi recent tasks/events, which health
check first failed, and whether any production VM or datastore was modified.
Do not include credentials or proxy configuration bodies.

## Successful rollback state

Rollback is complete when Intel ESXi 6.7 is stable, only the old
`Openwrt_Jump63` owns `.254`, PassWall/DNS/proxy checks pass, `.110` and Sidecar
are healthy, and no Cloudflare/pool/firewall/route/subscription change was
needed. Leave the new VM and T5 powered off/intact for later forensic review;
do not immediately retry the migration.
