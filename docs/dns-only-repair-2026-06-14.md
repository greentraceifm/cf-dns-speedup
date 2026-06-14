# OpenWrt CFIP DNS-Only Repair

Date: 2026-06-14

## Incident

The `auto` node group showed poor 4K playback around the morning usage window. Read-only checks found that the primary slots were healthy, but the exposed competitive slots had degraded:

```text
auto  -> 104.17.130.225 healthy
auto1 -> 104.17.136.166 healthy
auto2 -> 104.17.156.195 healthy
auto3 -> 104.20.29.46  degraded
auto4 -> 104.26.7.78   degraded
```

Latest validation before repair:

```text
104.17.130.225 -> 7.80 MB/s
104.17.136.166 -> 7.33 MB/s
104.17.156.195 -> 7.62 MB/s
104.20.29.46   -> 0.54 MB/s
104.26.7.78    -> 0.25 MB/s
```

## Root Cause

The exposed-slot guard code had already been deployed, but Cloudflare DNS still contained the earlier morning `auto3/auto4` competitive IPs. Clients or PassWall groups that rotated across `auto` through `auto4` could hit the degraded competitive slots.

## Repair

Performed a DNS-only update. No speed test, PassWall restart, cron change, token change, firewall change, or package change was performed.

Changed:

```text
auto3: 104.20.29.46 -> 104.17.130.225
auto4: 104.26.7.78  -> 104.17.136.166
```

Unchanged:

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
```

## Verification

After one TTL, router DNS and Cloudflare API matched:

```text
auto  -> 104.17.130.225
auto1 -> 104.17.136.166
auto2 -> 104.17.156.195
auto3 -> 104.17.130.225
auto4 -> 104.17.136.166
```

Post-repair validation:

```text
104.17.130.225 -> min 7.76 MB/s, avg 8.50 MB/s
104.17.136.166 -> min 7.40 MB/s, avg 7.96 MB/s
104.17.156.195 -> min 7.01 MB/s, avg 7.04 MB/s
104.17.130.225 -> min 8.95 MB/s, avg 9.01 MB/s
104.17.136.166 -> min 8.13 MB/s, avg 8.15 MB/s
```

## Follow-Up

The next normal automatic run should use the exposed-slot guard and avoid publishing degraded competitive slots. If future morning degradation recurs, check whether DNS was updated before the guard was available, or whether local DNS/PassWall caching held old `auto3/auto4` values past TTL.
