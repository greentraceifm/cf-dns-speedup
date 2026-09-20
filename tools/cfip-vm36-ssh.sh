#!/usr/bin/env bash
set -Eeuo pipefail

key=/home/ubuntu/.ssh/id_ed25519_cfip_vm36_maint
known_hosts=/home/ubuntu/.ssh/known_hosts

case "${1:---check}" in
  --check)
    [ "$#" -le 1 ] || exit 64
    remote='test "$(id -u)" = 0 && printf "VM36_KEY_AUTH=PASS\n"'
    ;;
  --stdin)
    [ "$#" -eq 1 ] || exit 64
    remote='sh -s'
    ;;
  *)
    printf 'Usage: %s [--check|--stdin]\n' "$0" >&2
    exit 64
    ;;
esac

[ -r "$key" ] && [ -r "$known_hosts" ] || {
  printf 'VM36 maintenance key or known_hosts is missing; no password fallback.\n' >&2
  exit 66
}

exec /usr/bin/ssh -F /dev/null -T \
  -i "$key" \
  -o IdentitiesOnly=yes \
  -o IdentityAgent=none \
  -o BatchMode=yes \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile="$known_hosts" \
  -o GlobalKnownHostsFile=/dev/null \
  -o UpdateHostKeys=no \
  -o ForwardAgent=no \
  -o ClearAllForwardings=yes \
  -o ConnectTimeout=10 \
  -o ConnectionAttempts=1 \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=2 \
  root@192.168.1.254 "$remote"
