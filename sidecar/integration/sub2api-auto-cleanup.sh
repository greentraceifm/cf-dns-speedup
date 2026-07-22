#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

exec 9>/run/lock/sub2api-auto-cleanup.lock
flock -n 9 || exit 0

DEPLOY_DIR=/opt/sub2api-deploy
BACKUP_DIR="$DEPLOY_DIR/backups"
LOG_DIR="$DEPLOY_DIR/data/logs"

echo "cleanup_started=$(date -Is)"
df -h /

# This is a multi-project Docker host. Named networks and tagged images can be
# intentionally idle between scheduled jobs, so a host-wide combined prune is
# unsafe even with an age filter. Preserve those resources and restrict this
# policy to old stopped containers and old dangling images.
preserved_network_ids="$(docker network ls -q | sort -u)"
preserved_tagged_image_ids="$(docker image ls --filter dangling=false -q | sort -u)"

docker container prune -f --filter 'until=168h'
docker image prune -f --filter 'until=168h'

for resource_id in $preserved_network_ids; do
  docker network inspect "$resource_id" >/dev/null 2>&1 || {
    echo "ERROR: preserved Docker network disappeared during cleanup: $resource_id" >&2
    exit 1
  }
done
for resource_id in $preserved_tagged_image_ids; do
  docker image inspect "$resource_id" >/dev/null 2>&1 || {
    echo "ERROR: preserved tagged Docker image disappeared during cleanup: $resource_id" >&2
    exit 1
  }
done

# This host uses the Engine's BuildKit cache but does not have the buildx CLI
# plugin. Prune that cache through the official Engine API with the same age
# boundary; this never touches images, containers, or volumes.
docker_api="$(docker version --format '{{.Server.APIVersion}}')"
curl -fsS --unix-socket /var/run/docker.sock -X POST \
  "http://localhost/v${docker_api}/build/prune?all=1&filters=%7B%22until%22%3A%7B%22168h%22%3Atrue%7D%7D"
echo

find "$LOG_DIR" -type f -name '*.log.gz' -mtime +3 -print -delete 2>/dev/null || true
find "$LOG_DIR" -type f -name '*.log' -size +200M -print -exec truncate -s 0 {} \; 2>/dev/null || true

find "$BACKUP_DIR" -maxdepth 1 -type d -name 'ops-log-cleanup-*' -mtime +14 -print -exec rm -rf -- {} + 2>/dev/null || true
while IFS= read -r -d '' sql_file; do
  if [ ! -f "${sql_file}.gz" ]; then
    echo "compressing=$sql_file"
    gzip -9 "$sql_file"
  fi
done < <(find "$BACKUP_DIR" -type f -name '*.sql' -mtime +1 -print0 2>/dev/null)

latest_sql_backup="$(find "$BACKUP_DIR" -type f \( -name '*.sql' -o -name '*.sql.gz' \) -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || true)"
while IFS= read -r -d '' gz_file; do
  if [ -n "$latest_sql_backup" ] && [ "$gz_file" = "$latest_sql_backup" ]; then
    continue
  fi
  echo "deleting_old_sql_backup=$gz_file"
  rm -f -- "$gz_file"
done < <(find "$BACKUP_DIR" -type f -name '*.sql.gz' -mtime +14 -print0 2>/dev/null)

journalctl --vacuum-time=14d
df -h /
echo "cleanup_finished=$(date -Is)"
