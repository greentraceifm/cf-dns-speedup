# cf-dns-speedup

Readable OpenWrt script for selecting a fast Cloudflare CDN IP and updating one Cloudflare DNS record.

This is a safer replacement for `curl | bash` style scripts:

- No obfuscation.
- No automatic proxy plugin stop/start.
- Uses Cloudflare API Token instead of Global API Key.
- Adds a total timeout around CloudflareSpeedTest so the job cannot hang forever.
- First run defaults to `DRY_RUN=1`, so Cloudflare DNS is not changed until you explicitly allow it.

## OpenWrt Install

One-line install from this GitHub repository:

```sh
curl -fsSL https://raw.githubusercontent.com/greentraceifm/cf-dns-speedup/main/install-openwrt.sh | sh
```

If GitHub raw cache has not refreshed after a new release, use the pinned commit installer:

```sh
curl -fsSL https://raw.githubusercontent.com/greentraceifm/cf-dns-speedup/ea8ec328706a5b7f5e1bf8a5d2e3b616b4327a6b/install-openwrt.sh | sh
```

The installer creates `/root/cf-dns-speedup` and downloads the runtime files.
After installation it opens an interactive setup menu similar to the original project.

Open the menu again later:

```sh
/root/cf-dns-speedup/menu.sh
```

Manual install:

```sh
mkdir -p /root/cf-dns-speedup
cd /root/cf-dns-speedup
```

Copy these files into the directory:

- `cf-dns-speedup.sh`
- `config.example.env`
- `menu.sh`

Then:

```sh
cp config.example.env config.env
chmod +x cf-dns-speedup.sh
chmod +x menu.sh
chmod 600 config.env
./menu.sh
```

Keep `DRY_RUN=1` for the first test.

## First-Time Setup Flow

After install, use the menu:

```sh
/root/cf-dns-speedup/menu.sh
```

Choose `1. 安装/首次配置`, then fill in:

```sh
CF_API_TOKEN="your_cloudflare_api_token"
CF_ZONE_ID="your_cloudflare_zone_id"
CF_RECORD_NAME="best.example.com"
```

For the first run, keep:

```sh
DRY_RUN=1
```

Then choose `3. 立即执行优选并更新 DNS`.

You can also run directly:

```sh
/root/cf-dns-speedup/cf-dns-speedup.sh
cat /root/cf-dns-speedup/run.log
```

If the log says `dry-run: would update ...`, the script is working and Cloudflare DNS was not changed.

Only then set:

```sh
DRY_RUN=0
```

Run again to really update Cloudflare DNS.

## Cloudflare Token

Create a Cloudflare API Token with:

- `Zone:Read`
- `DNS:Edit`
- Scope limited to the target zone only

Do not use the Global API Key.

## Menu Compatibility

The menu intentionally follows the original project's workflow:

- `1. 安装/首次配置`
- `2. 变更参数配置`
- `3. 立即执行优选并更新 DNS`
- `4. 域名清理`
- `5. 卸载脚本`

The `变更参数配置` submenu keeps the original 1-13 style options where practical.

Some high-risk original behaviors are intentionally disabled or made explicit:

- No obfuscated `eval` or nested `base64 | bash`.
- No automatic stop/start of PassWall, OpenClash, or other proxy plugins.
- No automatic batch deletion of Cloudflare DNS records.
- No Global API Key; use least-privilege Cloudflare API Token.
- `cfst` is wrapped by `CFST_TOTAL_TIMEOUT` to avoid hanging forever.
- First run keeps `DRY_RUN=1` so DNS is not changed until you switch it off.

## Repository Privacy

This repository is currently public:

```text
https://github.com/greentraceifm/cf-dns-speedup
```

Public means other people can see the script and documentation. This is acceptable for this project because real secrets are not committed. Keep actual values only in `/root/cf-dns-speedup/config.env` on your OpenWrt device.

Never commit:

- `config.env`
- Cloudflare API tokens
- Cloudflare Global API Key
- real Telegram or PushPlus tokens

If you want to make the repository private:

```sh
gh repo edit greentraceifm/cf-dns-speedup --visibility private
```

Note: a private repository will break the simple public one-line `curl` install unless you use authenticated GitHub access or another private delivery method.

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
