#!/usr/bin/env bash
set -Eeuo pipefail

umask 077
ASSET_DIR="${SIDECAR_ASSET_DIR:-/opt/cfip-sidecar/assets}"
DATA_DIR="${SIDECAR_DATA_DIR:-/var/lib/cfip-sidecar}"
IMAGE="${SIDECAR_RUNTIME_IMAGE:-cfip-sidecar-runtime:20260714}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

[ "$(id -u)" -eq 0 ] || { echo "must run as root" >&2; exit 1; }
for file in "$ASSET_DIR/xray" "$ASSET_DIR/cfst" "$ASSET_DIR/ip.txt"; do
  [ -s "$file" ] || { echo "missing asset: $file" >&2; exit 1; }
done
command -v "$DOCKER_BIN" >/dev/null 2>&1 || { echo "Docker is unavailable" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "host curl is unavailable" >&2; exit 1; }

ROOTFS="$TMP_DIR/rootfs"
mkdir -p "$ROOTFS/usr/local/bin" "$ROOTFS/usr/bin" "$ROOTFS/usr/lib" "$ROOTFS/lib64" "$ROOTFS/etc/ssl/certs"
install -m 0755 "$ASSET_DIR/xray" "$ROOTFS/usr/local/bin/xray"
install -m 0755 "$ASSET_DIR/cfst" "$ROOTFS/usr/local/bin/cfst"
install -m 0644 /etc/ssl/certs/ca-certificates.crt "$ROOTFS/etc/ssl/certs/ca-certificates.crt"
install -m 0755 /usr/bin/curl "$ROOTFS/usr/bin/curl"
LC_ALL=C ldd /usr/bin/curl >"$TMP_DIR/curl-ldd.txt"
grep -oE '/[^[:space:]()]+' "$TMP_DIR/curl-ldd.txt" | sort -u >"$TMP_DIR/curl-libs.txt"
if [ "$(wc -l < "$TMP_DIR/curl-libs.txt")" -lt 10 ]; then
  echo "curl dependency discovery is incomplete" >&2
  cat "$TMP_DIR/curl-ldd.txt" >&2
  exit 1
fi
while IFS= read -r lib; do
  case "$lib" in
    /lib64/*) install -m 0755 "$lib" "$ROOTFS/lib64/$(basename "$lib")" ;;
    *) install -m 0644 "$lib" "$ROOTFS/usr/lib/$(basename "$lib")" ;;
  esac
done <"$TMP_DIR/curl-libs.txt"
[ "$(find "$ROOTFS/usr/lib" -type f | wc -l)" -ge 10 ] || { echo "curl library collection is incomplete" >&2; exit 1; }
[ -x "$ROOTFS/lib64/ld-linux-x86-64.so.2" ] || { echo "curl dynamic loader is missing" >&2; exit 1; }
chmod -R a+rX "$ROOTFS"
cat >"$TMP_DIR/Dockerfile" <<'EOF'
FROM scratch
COPY rootfs /
ENV LD_LIBRARY_PATH=/usr/lib
ENTRYPOINT ["/usr/local/bin/xray"]
EOF
"$DOCKER_BIN" build --no-cache --network=none --pull=false -t "$IMAGE" "$TMP_DIR" >/dev/null
"$DOCKER_BIN" run --rm --network none --user 65532:65532 --entrypoint /usr/bin/curl "$IMAGE" --version >/dev/null
"$DOCKER_BIN" run --rm --network none --user 65532:65532 --entrypoint /usr/local/bin/xray "$IMAGE" version >/dev/null
mkdir -p "$DATA_DIR"
"$DOCKER_BIN" image inspect --format '{{.Id}}' "$IMAGE" >"$DATA_DIR/runtime-image.id"
chmod 0600 "$DATA_DIR/runtime-image.id"
echo "runtime_image=$IMAGE"
echo "runtime_image_id=$(cat "$DATA_DIR/runtime-image.id")"
