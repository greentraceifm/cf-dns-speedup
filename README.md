# cf-dns-speedup

Readable OpenWrt script for selecting a fast Cloudflare CDN IP and updating one Cloudflare DNS record.

This is a safer replacement for `curl | bash` style scripts:

- No obfuscation.
- No automatic proxy plugin stop/start.
- Uses Cloudflare API Token instead of Global API Key.
- Adds a total timeout around CloudflareSpeedTest so the job cannot hang forever.
- First run defaults to `DRY_RUN=1`, so Cloudflare DNS is not changed until you explicitly allow it.

## OpenWrt Install

```sh
mkdir -p /root/cf-dns-speedup
cd /root/cf-dns-speedup
```

Copy these files into the directory:

- `cf-dns-speedup.sh`
- `config.example.env`

Then:

```sh
cp config.example.env config.env
chmod +x cf-dns-speedup.sh
chmod 600 config.env
vi config.env
```

Keep `DRY_RUN=1` for the first test.

## Cloudflare Token

Create a Cloudflare API Token with:

- `Zone:Read`
- `DNS:Edit`
- Scope limited to the target zone only

Do not use the Global API Key.

## First Test

```sh
/root/cf-dns-speedup/cf-dns-speedup.sh
cat /root/cf-dns-speedup/run.log
```

If the log says `dry-run: would update ...`, the script is working without changing DNS.

Then set:

```sh
DRY_RUN=0
```

Run again.

## Cron Example

Run every day at 03:00:

```cron
0 3 * * * /root/cf-dns-speedup/cf-dns-speedup.sh >/tmp/cf-dns-speedup.cron.log 2>&1
```

## Troubleshooting

If the script stops at speed test, it will now fail after `CFST_TOTAL_TIMEOUT` seconds instead of hanging forever.

Useful conservative settings for routers:

```sh
CFST_THREADS=16
CFST_COUNT=3
CFST_TOTAL_TIMEOUT=600
CFST_URL=""
```

If you want real download speed testing, set a URL such as:

```sh
CFST_URL="https://speed.cloudflare.com/__down?bytes=104857600"
```

Latency-only mode is often more stable on OpenWrt.
