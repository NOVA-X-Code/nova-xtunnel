#!/bin/bash
# NOVA-XTUNNEL Menu & Core Installer
# Version: 2.2.0 - Premium Edition
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Must be root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Error: This script must be run as root.${NC}"
   exit 1
fi

clear
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║                                                              ║${NC}"
echo -e "${PURPLE}║     ${BLUE}NOVA-XTUNNEL${NC} | ${CYAN}Menu & SSH Core Infrastructure${NC}        ${PURPLE}║${NC}"
echo -e "${PURPLE}║     ${YELLOW}v2.2.0 - Optimized Deployment${NC}                         ${PURPLE}║${NC}"
echo -e "${PURPLE}║                                                              ║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Mandatory Dependencies Check
echo -e "\n${BLUE}🔍 Checking system environment...${NC}"
for cmd in wget python3 pip3; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${YELLOW}⚠️  Installing missing dependency: $cmd...${NC}"
        apt-get update -qq && apt-get install -y $cmd -qq > /dev/null
    fi
done
echo -e "${GREEN}✅ Environment ready.${NC}"

# Configuration
MENU_URL="https://raw.githubusercontent.com/nova-x-code/nova-xtunnel/main/menu.sh"
SSHD_URL="https://raw.githubusercontent.com/nova-x-code/nova-xtunnel/main/ssh"
CORE_DIR="/etc/nova-xtunnel"
LOG_DIR="/var/log/nova-xtunnel-panel"

# 1. Prepare Directory Structure
echo -e "${BLUE}📁 Initializing filesystem...${NC}"
mkdir -p "$CORE_DIR/bandwidth/pidtrack"
mkdir -p "$LOG_DIR"
touch "$CORE_DIR/users.db"
chmod -R 750 "$CORE_DIR"

# 2. Deploy Menu System
echo -e "${BLUE}📥 Downloading Management Menu...${NC}"
if wget -4 -q -O /usr/local/bin/menu "$MENU_URL"; then
    chmod +x /usr/local/bin/menu
    # Create alias for lowercase 'menu' just in case
    echo -e "${GREEN}✅ Menu system deployed to /usr/local/bin/menu${NC}"
else
    echo -e "${RED}❌ Critical Error: Could not fetch menu script.${NC}"
    exit 1
fi

# 3. Secure SSH Configuration
echo -e "${BLUE}⚙️  Hardening SSH Configuration...${NC}"
SSHD_CONFIG="/etc/ssh/sshd_config"
TIMESTAMP=$(date +%s)
BACKUP="$SSHD_CONFIG.bak.$TIMESTAMP"

cp "$SSHD_CONFIG" "$BACKUP"
echo -e "${CYAN}ℹ️  Safety backup created: $BACKUP${NC}"

if wget -4 -q -O "$SSHD_CONFIG" "$SSHD_URL"; then
    chmod 600 "$SSHD_CONFIG"

    # Validation step
    if sshd -t; then
        echo -e "${GREEN}✅ SSH configuration verified and applied.${NC}"
    else
        echo -e "${RED}❌ Validation failed! Reverting to backup...${NC}"
        cp "$BACKUP" "$SSHD_CONFIG"
        exit 1
    fi
else
    echo -e "${RED}❌ Error: SSH template download failed.${NC}"
    exit 1
fi

# 4. Service Reload
restart_ssh() {
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || service ssh restart 2>/dev/null
}

echo -e "${BLUE}🔄 Restarting encryption node...${NC}"
if restart_ssh; then
    echo -e "${GREEN}✅ SSH node operational.${NC}"
else
    echo -e "${YELLOW}⚠️  Manual restart required: 'systemctl restart ssh'${NC}"
fi

# 5. Environment Hook
echo -e "\n${YELLOW}🛠️  Finalizing system hooks...${NC}"
# Pre-configure common tools
apt-get install -y net-tools bc jq curl -qq > /dev/null

# Execute initial internal setup from the menu
bash /usr/local/bin/menu --install-setup > /dev/null

echo -e "\n${PURPLE}══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}SUCCESS: NOVA-XTUNNEL CORE INSTALLED${NC}"
echo -e "  ${CYAN}Commands:${NC}"
echo -e "  - Type ${YELLOW}'menu'${NC} to open the control center"
echo -e "  - All logs are stored in ${CYAN}$LOG_DIR${NC}"
echo -e "${PURPLE}══════════════════════════════════════════════════════════════${NC}\n"
