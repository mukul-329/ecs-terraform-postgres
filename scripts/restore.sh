#!/usr/bin/env bash
set -Eeuo pipefail

if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

DB_CONTAINER="${DB_CONTAINER:-booking-postgres}"
DB_USER="${POSTGRES_USER:-appuser}"
TARGET_DB="${2:-${RESTORE_DB:-bookingdb_restore}}"
BACKUP_FILE="${1:-}"

command -v docker >/dev/null 2>&1 || { echo "ERROR: docker is required" >&2; exit 1; }
docker inspect "$DB_CONTAINER" >/dev/null 2>&1 || {
  echo "ERROR: container '$DB_CONTAINER' not found. Start it with: docker compose up -d" >&2
  exit 1
}

if [[ -z "$BACKUP_FILE" ]]; then
  BACKUP_DIR="${BACKUP_DIR:-backups}"
  BACKUP_FILE="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.dump' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2-)"
fi

[[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]] || {
  echo "ERROR: backup file not found. Run ./scripts/backup.sh first." >&2
  exit 1
}
[[ "$TARGET_DB" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || {
  echo "ERROR: invalid target database name: $TARGET_DB" >&2
  exit 1
}
[[ "$TARGET_DB" != "bookingdb" ]] || {
  echo "ERROR: refusing to overwrite the source database bookingdb" >&2
  exit 1
}

docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" >/dev/null
echo "Recreating target database '$TARGET_DB'..."
docker exec "$DB_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$DB_USER" -d postgres \
  -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$TARGET_DB' AND pid <> pg_backend_pid();" >/dev/null
docker exec "$DB_CONTAINER" dropdb --if-exists -U "$DB_USER" "$TARGET_DB"
docker exec "$DB_CONTAINER" createdb -U "$DB_USER" "$TARGET_DB"

echo "Restoring '$BACKUP_FILE' into '$TARGET_DB'..."
docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$TARGET_DB" \
  --no-owner --no-privileges --exit-on-error < "$BACKUP_FILE"

echo "Restore completed. Verify with:"
echo "docker compose exec -T db psql -U $DB_USER -d $TARGET_DB -c 'SELECT COUNT(*) FROM hotel_bookings;'"
