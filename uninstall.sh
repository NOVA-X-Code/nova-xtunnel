#!/bin/bash
# NOVA-XTUNNEL Web Panel Uninstall Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PANEL_DIR="/var/www/nova-xtunnel-panel"

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║         NOVA-XTUNNEL Web Panel Uninstall Script              ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ This script must be run as root${NC}"
   exit 1
fi

echo -e "\n${RED}⚠️  WARNING: This will completely remove NOVA-XTUNNEL Web Panel${NC}"
echo -e "${YELLOW}This action is IRREVERSIBLE!${NC}\n"

read -p "Type 'yes' to confirm uninstall: " confirm

if [[ "$confirm" != "yes" ]]; then
    echo -e "${GREEN}Uninstall cancelled${NC}"
    exit 0
fi

# Ask about keeping database
read -p "Keep database backup? (y/n) [y]: " keep_db
keep_db=${keep_db:-y}

if [[ "$keep_db" == "y" || "$keep_db" == "Y" ]]; then
    BACKUP_DIR="/root/backups/nova-xtunnel"
    mkdir -p "$BACKUP_DIR"
    DATE=$(date +%Y%m%d_%H%M%S)
    if [ -f "$PANEL_DIR/panel.db" ]; then
        cp "$PANEL_DIR/panel.db" "$BACKUP_DIR/panel_backup_$DATE.db"
        echo -e "${GREEN}✅ Database backed up to $BACKUP_DIR/panel_backup_$DATE.db${NC}"
    fi
fi

echo -e "\n${YELLOW}🗑️  Removing components...${NC}"

# Stop and disable services
systemctl stop nova-xtunnel-panel 2>/dev/null
systemctl disable nova-xtunnel-panel 2>/dev/null
rm -f /etc/systemd/system/nova-xtunnel-panel.service

# Remove Nginx config if exists
if [ -f /etc/nginx/sites-available/nova-xtunnel-panel ]; then
    rm -f /etc/nginx/sites-available/nova-xtunnel-panel
    rm -f /etc/nginx/sites-enabled/nova-xtunnel-panel
    systemctl reload nginx 2>/dev/null
fi

# Remove panel directory
rm -rf "$PANEL_DIR"

# Remove cron jobs
crontab -l 2>/dev/null | grep -v "nova-xtunnel-panel" | crontab - 2>/dev/null

systemctl daemon-reload

echo -e "${GREEN}✅ Uninstall complete!${NC}"
echo -e "\n${YELLOW}Remaining files (if any):${NC}"
echo -e "  - /etc/nova-xtunnel/ (SSH core config)"
echo -e "  - /root/backups/nova-xtunnel/ (backups if created)"
echo -e "\n${GREEN}Thank you for using NOVA-XTUNNEL!${NC}"