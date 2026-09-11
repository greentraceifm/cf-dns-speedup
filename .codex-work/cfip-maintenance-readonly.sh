#!/usr/bin/env bash
set -Eeuo pipefail

if [ "$#" -ne 0 ]; then
  printf 'usage: %s\n' "$0" >&2
  exit 64
fi

ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=yes \
  ollama-server \
  'sudo -n /usr/local/sbin/cfip-maintenance-audit'
