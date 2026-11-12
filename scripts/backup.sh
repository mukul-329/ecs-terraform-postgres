#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

DB_CONTAINER="${DB_CONTAINER:-booking-postgres}"
DB_NAME="${POSTGRES-DB:-bookingdb}"
DB_USER="${POSTGRES_USER:-appuser}"
BACKUP_DIR="${BACKUP_DIR:-backups}"
TIMESTAMP="$(date -u +'%Y%m%d_%H%M%S')"
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.dump"

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required" >&2; exit 1; }
docker inspect "$DB_CONTAINER" >/dev/null 2>&1 || {
  echo "ERROR: container '$DB_CONTAINER' not found. Start it with: docker compose up -d" >&2
  exit 1
}
mkdir -p "$BACKUP_DIR"
docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null

echo "Creating PostgreSQL custom-format backup: $BACKUP_FILE"
docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc \
  > "$BACKUP_FILE"
test -s "$BACKUP_FILE" || { rm -f "$BACKUP_FILE"; echo "ERROR: backup is empty" >&2; exit 1; }
echo "Backup completed: $BACKUP_FILE"
