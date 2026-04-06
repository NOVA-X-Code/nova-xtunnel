#!/bin/bash
# NOVA-XTUNNEL Web Panel Backup Script

set -e

BACKUP_DIR="/root/backups/nova-xtunnel"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

mkdir -p "$BACKUP_DIR"

echo "Starting NOVA-XTUNNEL backup at $(date)"

# Backup database
if [ -f "/var/www/nova-xtunnel-panel/panel.db" ]; then
    cp "/var/www/nova-xtunnel-panel/panel.db" "$BACKUP_DIR/panel_backup_$DATE.db"
    echo "✅ Database backed up"
else
    echo "❌ Database not found"
fi

# Backup SSH configuration
if [ -d "/etc/nova-xtunnel" ]; then
    tar -czf "$BACKUP_DIR/ssh_config_backup_$DATE.tar.gz" /etc/nova-xtunnel/
    echo "✅ SSH configuration backed up"
fi

# Backup panel files
if [ -d "/var/www/nova-xtunnel-panel" ]; then
    tar -czf "$BACKUP_DIR/panel_files_backup_$DATE.tar.gz" \
        --exclude="venv" \
        --exclude="*.pyc" \
        --exclude="__pycache__" \
        /var/www/nova-xtunnel-panel/
    echo "✅ Panel files backed up"
fi

# Create backup info file
cat > "$BACKUP_DIR/backup_info_$DATE.txt" << EOF
Backup Date: $(date)
Hostname: $(hostname)
IP: $(curl -s -4 icanhazip.com 2>/dev/null || echo "Unknown")
Panel Version: $(grep -oP 'v\d+\.\d+\.\d+' /var/www/nova-xtunnel-panel/app.py 2>/dev/null || echo "Unknown")
EOF

# Clean old backups
find "$BACKUP_DIR" -name "*.db" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -name "backup_info_*.txt" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $BACKUP_DIR/panel_backup_$DATE.db"
echo "Old backups (older than $RETENTION_DAYS days) removed"
