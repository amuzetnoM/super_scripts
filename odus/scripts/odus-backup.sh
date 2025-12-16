#!/bin/bash
 
BACKUP_DIR="/var/backups/odus"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/odus_backup_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating ODUS configuration backup..."

# Backup important configs
tar -czf "$BACKUP_FILE" \
    /etc/odus \
    /opt/odus/intelligence \
    /root/.zshrc \
    /root/.config 2>/dev/null || true

# Keep only last 10 backups
ls -t $BACKUP_DIR/odus_backup_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null || true

echo "Backup completed: $BACKUP_FILE"
