# Upstream Profile Isolated Probe - 2026-07-22

## Scope

This was a bounded, no-cutover experiment to determine whether an existing
non-`auto` PassWall profile could materially outperform the current
Cloudflare-address path. It did not switch the active global or ACL node,
restart PassWall, modify UCI, update DNS or Cloudflare, change a pool, or edit
a subscription or credential.

The existing PassWall node benchmark was not used because it switches nodes
and restarts PassWall. Instead, PassWall's own Xray config generator created a
temporary independent SOCKS instance for each candidate in a private router
directory. Candidates were tested serially on ports 19100-19102. Each valid
candidate received Google and YouTube 204 checks followed by one 5 MiB
download. Maximum planned test traffic was about 15 MiB.

## Candidate Audit

There were five non-`auto` profile candidates among 24 PassWall nodes. Three
generated configurations passed the installed Xray core's config test. Two
failed config generation or validation and were excluded without repair:

- valid: `7Bj4Jnsg`, `7liz3A3X`, `792RubJ9`
- excluded: `Ak4RoAMc`, `JmKUBvn7`

The excluded profiles were not edited, and no subscription refresh was
attempted.

## Probe Result

| Profile | Google | YouTube | Data HTTP | Bytes | Speed | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `7Bj4Jnsg` | 204 | 204 | 200 | 5,242,880 | 1.76 MB/s | pass, no advantage |
| `7liz3A3X` | failed | failed | failed | 0 | 0.00 MB/s | fail |
| `792RubJ9` | 204 | 204 | 200 | 5,242,880 | 1.75 MB/s | pass, no advantage |

The two reachable alternatives were materially below the recent isolated
candidate path, which has been around 3.7-4.2 MB/s, and far below the unchanged
6.5 MB/s real-PassWall promotion gate. The failed profile had no usable HTTP
path. There was therefore no basis for a larger `20 MiB x 2` replication or a
production node switch. The experiment stopped at this first decision point.

## Router Postflight

The probe's internal guard reported `passwall_unchanged=1`. A separate
postflight confirmed:

- PassWall remained enabled with its original two Xray processes.
- Listeners 1070, 1041, 11400, and 15353 remained present.
- Temporary listeners 19100-19102 were absent.
- No `/tmp/cfip-upstream-probe.*` path or CFIP job remained.
- Router, OpenClaw, and PC Google/YouTube checks returned HTTP 204.
- All five `auto` records matched across LAN DNS, router DNS, and `1.1.1.1`.
- Cloudflare API was not rechecked.

No production setting was changed by this experiment.

## Independent Sidecar Finding

The read-only closeout found that the natural Sidecar run at 03:34:59 CST on
2026-07-22 exited before any Xray or download action. Its latest gate error was:

```text
sidecar ipvlan network is missing or invalid
```

The `cfip-direct` Docker network was absent at audit time. The timer remained
active and enabled, Docker PID remained 997, the four existing application
containers were healthy, the Sidecar lock was free, and no runtime Xray JSON
remained. The Sidecar host's Google and YouTube checks still returned 204.
Ollama had one resident model at audit time, but the recorded run failure was
the missing network gate, not an Ollama gate.

This is independent of the router-only upstream probe, but it blocks future
nightly Sidecar observations until the dedicated ipvlan network is recreated
and validated. Recreating it is a production write operation. Per the user's
stop-at-the-first-no-go instruction, no network repair or manual Sidecar run
was attempted.

## Decision

Close the current upstream-profile experiment with no winner and no production
change. Do not expand traffic, repair excluded profiles, switch PassWall, or
lower the 6.5 MB/s gate. A future upstream-capacity project would require a
genuinely new profile or server, not one of the existing alternatives tested
here.

Treat restoration of `cfip-direct` as a separate, narrowly reviewed runtime
repair. PassWall and the current Cloudflare DNS path remain healthy; the issue
is confined to the nightly isolated Sidecar observation path.
