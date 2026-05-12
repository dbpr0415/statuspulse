#!/usr/bin/env bash
# =============================================================================
# StatusPulse — Backup Script
# Dumps PostgreSQL, compresses, rotates (keep last 7), optional S3 upload
# Usage: bash scripts/backup.sh
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-/home/deploy/backups}"
DB_CONTAINER="${DB_CONTAINER:-statuspulse-db}"
DB_NAME="${DB_NAME:-statuspulse}"
DB_USER="${DB_USER:-postgres}"
MAX_BACKUPS=7
TIMESTAMP=$(date '+%Y-%m-%d_%H%M%S')
BACKUP_FILE="statuspulse_db_${TIMESTAMP}.sql.gz"
LOG_FILE="/var/log/statuspulse-backup.log"

# --- Logging -----------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Main --------------------------------------------------------------------
log "========================================="
log "🗄️  Starting PostgreSQL backup"
log "========================================="

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Dump the database
log "📦 Dumping database '${DB_NAME}' from container '${DB_CONTAINER}'..."
if docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" | gzip > "${BACKUP_DIR}/${BACKUP_FILE}"; then
    FILESIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    log "✅ Backup created: ${BACKUP_FILE} (${FILESIZE})"
else
    log "❌ Backup FAILED!"
    exit 1
fi

# Rotate old backups — keep only the last MAX_BACKUPS
log "🔄 Rotating backups (keeping last ${MAX_BACKUPS})..."
BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/statuspulse_db_*.sql.gz 2>/dev/null | wc -l)
if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
    REMOVE_COUNT=$((BACKUP_COUNT - MAX_BACKUPS))
    ls -1t "${BACKUP_DIR}"/statuspulse_db_*.sql.gz | tail -n "$REMOVE_COUNT" | while read -r old_backup; do
        log "🗑️  Removing old backup: $(basename "$old_backup")"
        rm -f "$old_backup"
    done
fi

# Optional: Upload to S3
if [ -n "${S3_BUCKET:-}" ]; then
    log "☁️  Uploading to S3: s3://${S3_BUCKET}/backups/${BACKUP_FILE}"
    if aws s3 cp "${BACKUP_DIR}/${BACKUP_FILE}" "s3://${S3_BUCKET}/backups/${BACKUP_FILE}"; then
        log "✅ S3 upload successful"
    else
        log "⚠️  S3 upload failed (backup is still saved locally)"
    fi
else
    log "ℹ️  S3_BUCKET not set — skipping cloud upload"
fi

# List current backups
log ""
log "📋 Current backups:"
ls -lh "${BACKUP_DIR}"/statuspulse_db_*.sql.gz 2>/dev/null | while read -r line; do
    log "   $line"
done

log "========================================="
log "✅ Backup complete"
log "========================================="
