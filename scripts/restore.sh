#!/bin/bash
# NOVA-XTUNNEL Web Panel Restore Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root${NC}"
   exit 1
fi

echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}         NOVA-XTUNNEL Web Panel Restore Script${NC}"
echo -e "${YELLOW}════════════════════════════════════════════════════════════${NC}"

# List available backups
BACKUP_DIR="/root/backups/nova-xtunnel"
if [ ! -d "$BACKUP_DIR" ]; then
    echo -e "${RED}❌ No backups found at $BACKUP_DIR${NC}"
    exit 1
fi

echo -e "\n${GREEN}Available backups:${NC}"
ls -lh "$BACKUP_DIR"/panel_backup_*.db 2>/dev/null | tail -10 || echo "No database backups found"

read -p "Enter backup file path (e.g., /root/backups/nova-xtunnel/panel_backup_20240101_120000.db): " BACKUP_FILE

if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}❌ Backup file not found${NC}"
    exit 1
fi

echo -e "\n${YELLOW}⚠️  This will overwrite current data${NC}"
read -p "Continue? (y/n): " confirm

if [[ "$confirm" != "y" ]]; then
    echo -e "${GREEN}Restore cancelled${NC}"
    exit 0
fi

# Stop panel
echo -e "${YELLOW}🛑 Stopping panel service...${NC}"
systemctl stop nova-xtunnel-panel

# Backup current data before restore
CURRENT_BACKUP="$BACKUP_DIR/pre_restore_backup_$(date +%Y%m%d_%H%M%S).db"
if [ -f "/var/www/nova-xtunnel-panel/panel.db" ]; then
    cp "/var/www/nova-xtunnel-panel/panel.db" "$CURRENT_BACKUP"
    echo -e "${GREEN}✅ Current data backed up to $CURRENT_BACKUP${NC}"
fi

# Restore database
echo -e "${YELLOW}📥 Restoring database...${NC}"
cp "$BACKUP_FILE" "/var/www/nova-xtunnel-panel/panel.db"
chmod 644 "/var/www/nova-xtunnel-panel/panel.db"

# Restore SSH config if available
SSH_BACKUP="${BACKUP_FILE%.db}.tar.gz"
SSH_BACKUP=$(echo "$SSH_BACKUP" | sed 's/panel_backup_/ssh_config_backup_/')
if [ -f "$SSH_BACKUP" ]; then
    echo -e "${YELLOW}📥 Restoring SSH configuration...${NC}"
    tar -xzf "$SSH_BACKUP" -C /
    echo -e "${GREEN}✅ SSH configuration restored${NC}"
fi

# Restart panel
echo -e "${YELLOW}🚀 Restarting panel service...${NC}"
systemctl start nova-xtunnel-panel

sleep 3

if systemctl is-active --quiet nova-xtunnel-panel; then
    echo -e "${GREEN}✅ Restore completed successfully!${NC}"
else
    echo -e "${RED}❌ Panel failed to start. Restoring previous data...${NC}"
    cp "$CURRENT_BACKUP" "/var/www/nova-xtunnel-panel/panel.db"
    systemctl restart nova-xtunnel-panel
    echo -e "${YELLOW}⚠️  Previous data restored. Please check logs.${NC}"
fi