#!/bin/bash
# NOVA-XTUNNEL Full Stack Installer
# Version: 2.2.0 - Premium Edition (CLI + Web Panel)
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

PANEL_DIR="/var/www/nova-xtunnel-panel"
CORE_DIR="/etc/nova-xtunnel"

clear
echo -e "${PURPLE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${PURPLE}║                                                              ║${NC}"
echo -e "${PURPLE}║     ${BLUE}NOVA-XTUNNEL${NC} | ${CYAN}Full Stack Premium Deployment${NC}         ${PURPLE}║${NC}"
echo -e "${PURPLE}║     ${YELLOW}CLI Menu + Web Control Panel + Python Limiter${NC}         ${PURPLE}║${NC}"
echo -e "${PURPLE}║                                                              ║${NC}"
echo -e "${PURPLE}╚══════════════════════════════════════════════════════════════╝${NC}"

# 1. System Preparation
echo -e "\n${BLUE}📦 [1/6] Installing system dependencies...${NC}"
apt-get update -qq
apt-get install -y python3 python3-pip python3-venv sqlite3 ufw curl wget git nginx net-tools bc jq -qq > /dev/null

mkdir -p "$CORE_DIR/bandwidth/pidtrack"
mkdir -p "$PANEL_DIR"
mkdir -p /var/log/nova-xtunnel-panel

# 2. SSH Hardening & CLI Menu
echo -e "${BLUE}⚙️  [2/6] Configuring SSH & CLI Menu...${NC}"
# Backup & Apply SSH Template
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)
wget -4 -q -O /etc/ssh/sshd_config "https://raw.githubusercontent.com/nova-x-code/nova-xtunnel/main/ssh"
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null

# Install Menu
wget -4 -q -O /usr/local/bin/menu "https://raw.githubusercontent.com/nova-x-code/nova-xtunnel/main/menu.sh"
chmod +x /usr/local/bin/menu

# 3. Web Panel Deployment
echo -e "${BLUE}🌐 [3/6] Deploying Web Infrastructure...${NC}"
# En production, on copierait les fichiers ici.
# Pour cet environnement, on assume que src/ est présent dans le dossier actuel.
cp -r src/* "$PANEL_DIR/" 2>/dev/null || true

# Virtual Environment
echo -e "${BLUE}🐍 [4/6] Setting up Python environment...${NC}"
python3 -m venv $PANEL_DIR/venv
source $PANEL_DIR/venv/bin/activate
pip install --upgrade pip -q
pip install flask flask-login flask-limiter bcrypt gunicorn requests python-dateutil -q

# 4. Database & Admin Setup
echo -e "\n${YELLOW}👤 Admin Account Setup:${NC}"
read -p "👉 Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
read -p "👉 Admin password: " ADMIN_PASS
if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 12)
    echo -e "${GREEN}🔑 Generated password: ${YELLOW}$ADMIN_PASS${NC}"
fi

python3 "$PANEL_DIR/init_db.py" "$ADMIN_USER" "$ADMIN_PASS" || true

# 5. Service Configuration
echo -e "${BLUE}⚙️  [5/6] Configuring Systemd Services...${NC}"

# Web Panel
cat > /etc/systemd/system/nova-xtunnel-panel.service << EOF
[Unit]
Description=Nova-XTunnel Web Control Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
Environment="PATH=$PANEL_DIR/venv/bin"
ExecStart=$PANEL_DIR/venv/bin/gunicorn --bind 127.0.0.1:5000 app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Python Limiter
cat > /etc/systemd/system/nova-xtunnel-limiter.service << EOF
[Unit]
Description=Nova-XTunnel High-Performance Limiter
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=$PANEL_DIR/venv/bin/python3 utils/limiter.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Nginx
cat > /etc/nginx/sites-available/nova-xtunnel << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /static {
        alias /var/www/nova-xtunnel-panel/static;
    }
}
EOF

ln -sf /etc/nginx/sites-available/nova-xtunnel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 6. Finalizing
echo -e "${BLUE}🚀 [6/6] Starting Nova-XTunnel Stack...${NC}"
systemctl daemon-reload
systemctl enable nginx nova-xtunnel-panel nova-xtunnel-limiter
systemctl restart nginx nova-xtunnel-panel nova-xtunnel-limiter

# Internal menu setup hook
bash /usr/local/bin/menu --install-setup > /dev/null

echo -e "\n${PURPLE}══════════════════════════════════════════════════════════════${NC}"
echo -e "  ${GREEN}✨ FULL STACK INSTALLATION COMPLETE ✨${NC}"
echo -e "\n  ${CYAN}🖥️  WEB PANEL:${NC} http://$(curl -s -4 icanhazip.com)"
echo -e "  ${CYAN}👤 ADMIN:${NC} $ADMIN_USER"
echo -e "  ${CYAN}🔑 PASS:${NC} $ADMIN_PASS"
echo -e "\n  ${CYAN}⌨️  CLI MENU:${NC} Type ${YELLOW}'menu'${NC} in terminal"
echo -e "${PURPLE}══════════════════════════════════════════════════════════════${NC}\n"
