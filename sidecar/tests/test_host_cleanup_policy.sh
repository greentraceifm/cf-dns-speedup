#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
POLICY="$ROOT/integration/sub2api-auto-cleanup.sh"

bash -n "$POLICY"

if grep -Eq '^[[:space:]]*docker[[:space:]]+system[[:space:]]+prune' "$POLICY"; then
  echo "host-wide docker system prune is forbidden" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*docker[[:space:]]+network[[:space:]]+prune' "$POLICY"; then
  echo "global Docker network pruning is forbidden" >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*docker[[:space:]]+image[[:space:]]+prune[[:space:]].*-a' "$POLICY"; then
  echo "pruning all unused tagged images is forbidden" >&2
  exit 1
fi

grep -Fq "docker container prune -f --filter 'until=168h'" "$POLICY"
grep -Fq "docker image prune -f --filter 'until=168h'" "$POLICY"
grep -Fq 'preserved_network_ids=' "$POLICY"
grep -Fq 'preserved_tagged_image_ids=' "$POLICY"
grep -Fq 'docker network inspect "$resource_id"' "$POLICY"
grep -Fq 'docker image inspect "$resource_id"' "$POLICY"
grep -Fq -- '--connect-timeout 5 --max-time "$BUILDKIT_PRUNE_MAX_SECONDS"' "$POLICY"
grep -Fq 'invalid BUILDKIT_PRUNE_MAX_SECONDS' "$POLICY"

echo "host cleanup policy test passed"
