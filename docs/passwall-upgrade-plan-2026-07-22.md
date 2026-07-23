# PassWall Xray core safe-upgrade plan - 2026-07-22

## Decision

Do not upgrade PassWall or Xray immediately. First accept a new natural
Sidecar cycle after the 2026-07-22 hardening. The first upgrade scope is
limited to one validated `xray-core` package. A full
`luci-app-passwall` upgrade is explicitly out of scope unless a separate
compatibility review identifies a concrete security or functional need.

The upgrade is fail-closed: if there is no newer package from the configured
signed source, if dependencies change, or if any preflight check fails, keep
the current runtime unchanged. Never use a blanket `opkg upgrade`.

## Current verified baseline

Read-only inventory at 2026-07-22 11:00 CST:

- Router: `192.168.1.254`, Kwrt `25.12.0-rc3`, target `x86/64`, architecture
  `x86_64`.
- `luci-app-passwall`: `26.6.2-r169`.
- Installed `xray-core` package: `26.6.1-r13`.
- Runtime binary: Xray `26.6.27`.
- Runtime health: two PassWall Xray processes and required listeners `1070`,
  `1041`, `11400`, and `15353` are present.
- The cached package index does not list PassWall or Xray as upgradable.
  Cached `xray-core` entries contain no version newer than the installed
  package. This is not evidence that the installed package is globally latest;
  a signed-source refresh is deferred to the controlled maintenance workflow.
- GitHub production baseline: `cf36cd5`.
- The next required Sidecar evidence is a natural cycle around
  2026-07-23 03:31 CST, followed by read-only acceptance around 04:30 CST.

## Upgrade boundary

Allowed:

- refresh and inspect the configured signed package source in a controlled
  window;
- stage exactly one architecture-matching `xray-core` IPK;
- stage the exact currently installed `xray-core` IPK as the prevalidated
  rollback package;
- verify package and binary hashes, metadata, control scripts, and dry-run
  dependency effects;
- test the candidate binary against the current generated PassWall runtime
  configurations without exposing their contents;
- install only the validated Xray package, restart PassWall once, and roll back
  once if acceptance fails.

Forbidden:

- upgrading `luci-app-passwall`, `sing-box`, SmartDNS, HAProxy, ChinaDNS,
  firewall components, firmware, LuCI, or unrelated dependencies;
- changing PassWall nodes, ACLs, subscriptions, credentials, TLS topology,
  routes, firewall rules, timers, Sidecar policy, Cloudflare DNS, candidate
  pools, stable pools, or `auto` records;
- lowering the real PassWall minimum throughput gate below `6.5 MB/s`;
- copying PassWall configuration, runtime JSON, subscriptions, UUIDs, tokens,
  or credentials away from the router.

## Hard preflight gates

All gates must pass in the same maintenance window:

1. A new natural Sidecar report is complete and successful; the service is
   inactive with `Result=success`, `ExecMainStatus=0`, and no MainPID.
2. Sidecar, CFIP, PassWall observation, package-manager, and maintenance locks
   are free; no scan or candidate update is running.
3. PassWall is enabled and healthy, with two Xray processes and all four
   required listeners. SmartDNS and dnsmasq are healthy.
4. Sidecar has no transient container, no attached `cfip-direct` container,
   and no `/run` Xray JSON residue. Docker and the four existing containers are
   healthy; Ollama is idle.
5. PC, jump host, Sidecar host, and router connectivity checks succeed.
   `auto` through `auto4` agree across router, LAN, and public DNS views.
6. The target package is bound to the configured signed source: verify the
   freshly fetched `Packages` index with the existing trusted key, then match
   its exact `Package`, `Version`, `Architecture`, `Filename`, `Size`, and
   `SHA256sum` fields to the staged IPK. Do not add or replace feed keys during
   the change window.
7. `opkg --noaction` against the exact staged path shows only the intended
   Xray change. Any additional install, removal, downgrade, or dependency
   replacement blocks the upgrade.
8. The staged binary reports the expected version and successfully validates
   every current PassWall Xray runtime configuration without printing config
   contents.
9. The exact currently installed Xray IPK is available, receives the same
   provenance and metadata checks, and its intentional local downgrade has
   been dry-run. A binary-only or manual opkg-database restore is not an
   acceptable rollback.
10. Candidate and rollback IPKs have no maintainer script or `conffiles`
    behavior that restarts services, changes UCI, firewall, DNS, feeds, keys,
    timers, subscriptions, or unrelated files.
11. Overlay and `/tmp` have sufficient free space and inodes for both IPKs,
    unpacked inspection, backup, and installation peak usage.
12. `uci changes passwall` is empty, the direct LAN management path works
    independently of PassWall, and a second recovery session is available.

## Backup and execution

Create `/root/openwrt-backup/passwall-xray-core-<timestamp>` with mode `0700`.
Keep all sensitive material on the router. Back up the current Xray binary,
`/etc/config/passwall`, opkg status, `xray-core` package metadata, and relevant
keep files. Set sensitive backups to mode `0600`, create a SHA256 manifest, and
verify that every backup is readable before installation. These copies are
evidence and emergency reference; do not restore or hand-edit the global opkg
database. Keep the verified current-version IPK beside the candidate for the
only supported package rollback.

Install the staged IPK only after all gates pass. Verify the installed binary
and current runtime configurations before performing exactly one PassWall
restart. Measure the proxy interruption from the last successful pre-restart
probe to the first fully successful post-restart probe.

## Acceptance and rollback

Acceptance requires:

- PassWall enabled and running with the expected new Xray version;
- two Xray processes and listeners `1070`, `1041`, `11400`, and `15353`;
- both Xray PIDs resolve through `/proc/<pid>/exe` to the installed binary,
  whose hash matches the staged payload;
- no new fatal, panic, invalid, or unsupported errors;
- unchanged node, ACL, TLS, DNS, and routing topology;
- successful HTTP checks from PC, jump host, Sidecar host, and router;
- successful project health, topology, and real PassWall path checks;
- healthy Sidecar timer/service, Docker, existing containers, Ollama, and free
  project locks;
- unchanged Cloudflare DNS, candidate pools, stable pools, and `auto` records.

If installation, config validation, restart, connectivity, listener, or
topology acceptance fails, stop all further work. Install the prevalidated
current-version IPK with the intentional downgrade option, restore PassWall
configuration only if it changed unexpectedly, then perform exactly one
restart and repeat the full acceptance suite. Do not manually restore opkg
status or package metadata, and do not attempt a second upgrade. If rollback
acceptance fails, leave DNS, firewall, routes, pools, and subscriptions
untouched and report the exact failure and backup path for manual recovery.

After a successful upgrade, observe multiple natural Sidecar and real PassWall
windows before closing the change. Sidecar candidates remain competition-only;
stable/auto promotion still requires the unchanged real PassWall
`>= 6.5 MB/s` gate.

## Record lifecycle

- Before a target package is validated: state is `deferred_no_validated_target`.
- After preflight and staging pass: append the target version, hashes, source,
  dependency dry run, and backup path without secrets.
- After execution: append measured interruption, acceptance results, and any
  rollback result.
- Only after successful observation should a no-secret summary be synchronized
  to long-term OpenClaw/Notion authority records.

## Independent review

On 2026-07-22, independent SRE, security, and OpenWrt/opkg compatibility
reviews each returned `PASS_WITH_CHANGES`. The controls above incorporate their
shared requirements. Installation remains blocked until the fresh natural
Sidecar acceptance, a newer signed-index-backed candidate, and the exact
verified rollback IPK are all available in the same observed maintenance
window.

## 2026-07-23 observed gate result

The post-hardening natural Sidecar gate passed. The service returned to
`inactive` with `Result=success`, `ExecMainStatus=0`, and no MainPID. The new
report `sidecar-observation-20260722-193225.tsv` contained five complete
candidates, all with HTTP 200. Their minimum measured rates were between
`4.19` and `4.41 MB/s`, so none met the unchanged real PassWall
`6.5 MB/s` promotion gate. Sidecar locks and cleanup checks passed; Docker,
the four existing containers, Ollama, host connectivity, PassWall processes
and listeners, and the three DNS views remained healthy. The Cloudflare API
was not rechecked.

A subsequent observed `opkg update` completed successfully for all seven
configured feeds. The refreshed `kwrt_kiddin9` package index advertises
`xray-core 26.7.11-r20` for `x86_64`, size `12315847`, SHA256
`ac1fcbfaafbf01c40d05767ecf1eb40aff33900130c438f88ea9fdc64a243d80`,
with only `libc` and `ca-bundle` dependencies. Those fields exactly match the
already staged candidate IPK.

Installation is nevertheless blocked by two mandatory controls:

- the configured feed does not provide `Packages.sig`, and the router has no
  enabled `check_signature` option, so the package index cannot be verified
  with the existing trusted keys;
- the exact installed rollback package, `xray-core 26.6.1-r13` for `x86_64`,
  is not present in the router staging or backup locations and is not
  available from the current package indexes with a verifiable provenance
  chain.

The state therefore remains `deferred_no_validated_target`. No package was
installed, PassWall was not restarted, and no runtime configuration, DNS,
route, pool, subscription, timer, or Cloudflare record was changed. A future
attempt may resume only after both a signed target-index chain and the exact
verified rollback IPK are available in the same controlled window.

### Same-day unblock attempt

An independent HTTP probe from the jump host confirmed that `Packages.gz`,
`Packages.manifest`, and the new `26.7.11-r20` IPK return HTTP 200, while both
`Packages.sig` and `xray-core_26.6.1-r13_x86_64.ipk` return HTTP 404. The feed
directory lists only the new Xray IPK. The maintainer's public
`kiddin9/op-packages` and `kiddin9/openwrt-passwall-packages` repositories
contain source recipes but publish no release assets or signed historical IPK.
A source recipe or third-party mirror is not an acceptable substitute for the
exact provenance-verified rollback package.

Before this investigation, a router-compatible `pidof`/`netstat` check again
confirmed two `/usr/bin/xray` processes and listeners `1070`, `1041`, `11400`,
and `15353`. The earlier zero result was a probe compatibility error because
this router does not provide `ss`; it was not a PassWall outage. No install,
restart, feed change, key change, or runtime modification was performed.
