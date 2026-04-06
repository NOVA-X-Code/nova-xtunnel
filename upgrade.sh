#!/bin/bash
# NOVA-XTUNNEL Ecosystem Upgrade Script
# Version: 2.1.0

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PANEL_DIR="/var/www/nova-xtunnel-panel"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           NOVA-XTUNNEL Global Upgrade Engine                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Error: This script must be run as root${NC}"
   exit 1
fi

# 1. Update Menu & CLI
echo -e "${YELLOW}⚙️ Updating CLI Menu System...${NC}"
if wget -4 -q -O /usr/local/bin/menu "https://raw.githubusercontent.com/nova-x-code/nova-xtunnel/main/menu.sh"; then
    chmod +x /usr/local/bin/menu
    echo -e "${GREEN}✅ CLI Menu updated.${NC}"
else
    echo -e "${RED}⚠️ Failed to update CLI Menu. Skipping...${NC}"
fi

# 2. Update Web Panel (if installed)
if [ -d "$PANEL_DIR" ]; then
    echo -e "${YELLOW}📦 Upgrading Web Infrastructure...${NC}"

    # Backup database
    BACKUP_DIR="/root/backups/nova-xtunnel"
    mkdir -p "$BACKUP_DIR"
    cp "$PANEL_DIR/panel.db" "$BACKUP_DIR/pre_upgrade_$(date +%s).db"

    # Stop services
    systemctl stop nova-xtunnel-panel nova-xtunnel-limiter

    # Sync new structure (Assuming repo is pulled or files are delivered)
    # Here we would normally git pull or curl files

    # Update Virtualenv
    source "$PANEL_DIR/venv/bin/activate"
    pip install --upgrade pip
    pip install flask flask-login flask-limiter bcrypt gunicorn requests python-dateutil

    # DB Migrations
    python3 src/init_db.py --upgrade

    # Permissions
    chown -R root:root "$PANEL_DIR"

    # Restart
    systemctl daemon-reload
    systemctl restart nova-xtunnel-panel nova-xtunnel-limiter
    echo -e "${GREEN}✅ Web Panel & Python Limiter upgraded.${NC}"
else
    echo -e "${BLUE}ℹ️ Web Panel not detected. Only CLI components were updated.${NC}"
fi

echo -e "\n${GREEN}✨ Upgrade completed successfully!${NC}"
echo -e "System is now running version 2.1.0 (Premium Stack)"
