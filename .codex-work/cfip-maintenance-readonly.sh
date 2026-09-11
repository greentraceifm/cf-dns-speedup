#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 1 ]; then
  printf 'usage: %s AUDIT_SCRIPT_ON_OPENCLAW\n' "$0" >&2
  exit 64
fi

audit_script="$1"
[ -r "$audit_script" ] || { printf 'audit script is unreadable\n' >&2; exit 66; }
case "$audit_script" in
  /*) ;;
  *) printf 'audit script must use an absolute path\n' >&2; exit 64 ;;
esac

ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=yes \
  ollama-server \
  "sudo -n sh -s" <"$audit_script"
