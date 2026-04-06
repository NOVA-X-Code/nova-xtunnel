#!/bin/bash
# NOVA-XTUNNEL Web Panel Installer v2.1
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

VERSION="2.1.0"
PANEL_DIR="/var/www/nova-xtunnel-panel"

# Must be root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Error: This script must be run as root.${NC}"
   exit 1
fi

clear
echo -e "${CYAN}"
cat << "EOF"
   _   _   ___   __     __   ___   _   _   _   _   ___   _   _   ___
  / \ | \ | \ \ / /     \ \ / / \ | \ | | | | | | / _ \ | \ | | |_ _|
 / _ \|  \| |\ V /       \ V / _ \|  \| | | | | || | | ||  \| |  | |
/ ___ \ |\  | | |        | | ___ \ |\  | | |_| || |_| || |\  |  | |
/_/   \_| \_| |_|        |_|   \_\_| \_|  \___/  \___/ |_| \_| |___|
EOF
echo -e "${NC}"

echo -e "\n${YELLOW}📋 Installation Wizard v${VERSION}${NC}"
echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"

# Dependencies
echo -e "\n${BLUE}📦 Installing system dependencies...${NC}"
apt-get update
apt-get install -y python3 python3-pip python3-venv sqlite3 ufw curl wget git nginx

# Directory structure
echo -e "${BLUE}📁 Preparing directories...${NC}"
mkdir -p $PANEL_DIR/src/utils
mkdir -p $PANEL_DIR/src/static/css
mkdir -p $PANEL_DIR/src/static/js
mkdir -p $PANEL_DIR/src/templates
mkdir -p /var/log/nova-xtunnel-panel
mkdir -p /etc/nova-xtunnel/bandwidth/pidtrack

# Sync current files to production path
echo -e "${BLUE}📥 Deploying source files...${NC}"
# Note: In a real scenario, we'd copy from the current repo dir
# For this simulation, we assume files are already in the project structure

# Create virtual environment
echo -e "${BLUE}🐍 Setting up Python environment...${NC}"
python3 -m venv $PANEL_DIR/venv
source $PANEL_DIR/venv/bin/activate
pip install --upgrade pip
# In production, we'd pip install -r requirements.txt
pip install flask flask-login flask-limiter bcrypt gunicorn requests python-dateutil

# Database Initialization
echo -e "${BLUE}🗄️ Initializing system database...${NC}"
# Check for admin input
read -p "👉 Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}
read -p "👉 Admin password: " ADMIN_PASS
if [[ -z "$ADMIN_PASS" ]]; then
    ADMIN_PASS=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 12)
    echo -e "${GREEN}🔑 Generated password: ${YELLOW}$ADMIN_PASS${NC}"
fi

python3 src/init_db.py "$ADMIN_USER" "$ADMIN_PASS"

# Service configurations
echo -e "${BLUE}⚙️ Configuring system services...${NC}"

# Web Panel Service
cat > /etc/systemd/system/nova-xtunnel-panel.service << EOF
[Unit]
Description=Nova-XTunnel Web Control Panel
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
Environment="PATH=$PANEL_DIR/venv/bin"
ExecStart=$PANEL_DIR/venv/bin/gunicorn --bind 127.0.0.1:5000 src.app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Limiter Service
cat > /etc/systemd/system/nova-xtunnel-limiter.service << EOF
[Unit]
Description=Nova-XTunnel Performance & Security Limiter
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
ExecStart=/usr/bin/python3 src/utils/limiter.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Nginx Configuration
cat > /etc/nginx/sites-available/nova-xtunnel << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /static {
        alias /var/www/nova-xtunnel-panel/src/static;
    }
}
EOF

ln -sf /etc/nginx/sites-available/nova-xtunnel /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Enable and start everything
echo -e "${BLUE}🚀 Starting Nova-XTunnel ecosystem...${NC}"
systemctl daemon-reload
systemctl enable nginx nova-xtunnel-panel nova-xtunnel-limiter
systemctl restart nginx nova-xtunnel-panel nova-xtunnel-limiter

echo -e "\n${GREEN}✅ Installation Complete!${NC}"
echo -e "${YELLOW}Panel Address:${NC} http://$(curl -s -4 icanhazip.com)"
echo -e "${YELLOW}Admin User:${NC} $ADMIN_USER"
echo -e "${YELLOW}Admin Pass:${NC} $ADMIN_PASS"
