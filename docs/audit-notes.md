# cdnopw Audit Notes

Downloaded source:

```sh
curl -ksSL https://gitlab.com/rwkgyg/cdnopw/raw/main/cdnopw.sh -o cdnopw.sh
```

## Findings

The downloaded `cdnopw.sh` is heavily obfuscated:

- 331 KB in only 3 lines.
- More than 12,000 small shell variables.
- Final execution uses `eval`.
- The first decoded layer runs nested `base64 -d | bash` wrappers.
- The final readable installer then downloads additional scripts and a `cfst` binary.
- `cdnac.sh` is also obfuscated.

This does not prove malicious behavior by itself, but it is not appropriate for a hardened home network router because the code cannot be reviewed before execution.

## Speed-Test Hang Cause

The main runtime script calls `./cfst` directly:

```sh
./cfst -tp "$port" ... -n "$threads" -dn "$count" ...
```

Problems:

- No total timeout around `cfst`.
- Default thread count is high for OpenWrt.
- No preflight check for the download test URL.
- No strong error handling if `cfst` never creates `result.csv`.
- Proxy plugin stop/start happens around the test, so a hang may leave services stopped.

## Safer Replacement

The replacement script in this directory:

- Uses readable Bash.
- Keeps proxy plugins untouched.
- Wraps `cfst` in `timeout`.
- Uses conservative defaults.
- Uses Cloudflare API Token with least privilege.
- Supports dry-run mode before changing DNS.
