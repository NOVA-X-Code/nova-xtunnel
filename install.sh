#!/bin/bash
# NOVA-XTUNNEL Web Panel Installer v2.0 (HTTPS Gunicorn Edition)
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

VERSION="2.0.0"
REPO_URL="https://raw.githubusercontent.com/nova-x-code/nova-xtunnel-webpanel/main"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     ${GREEN}NOVA-XTUNNEL Web Panel Installer v${VERSION}${BLUE}                     ║${NC}"
echo -e "${BLUE}║     ${CYAN}Secure SSH Tunnel Management Panel${BLUE}                            ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"

# Must be root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Error: This script must be run as root.${NC}"
   exit 1
fi

# Configuration variables
PANEL_DIR="/var/www/nova-xtunnel-panel"
PANEL_PORT=""
PANEL_SSL="false"
PANEL_DOMAIN=""
INSTALL_TYPE=""

# Function to check if port is available
check_port() {
    local port=$1
    if ss -tlnp | grep -q ":$port "; then
        return 1
    fi
    return 0
}

# Function to get available port
get_available_port() {
    local start_port=$1
    local port=$start_port
    while ! check_port $port; do
        port=$((port + 1))
    done
    echo $port
}

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

echo -e "\n${YELLOW}📋 Installation Wizard${NC}"
echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"

# Installation type
echo -e "\n${YELLOW}Select installation type:${NC}"
echo -e "  ${GREEN}[1]${NC} Full installation (Recommended)"
echo -e "  ${GREEN}[2]${NC} Minimal installation (Panel only)"
echo -e "  ${GREEN}[3]${NC} Update existing installation"
read -p "👉 Choice [1]: " INSTALL_TYPE
INSTALL_TYPE=${INSTALL_TYPE:-1}

if [[ "$INSTALL_TYPE" == "3" ]]; then
    echo -e "\n${BLUE}🔄 Updating NOVA-XTUNNEL Web Panel...${NC}"
    cd $PANEL_DIR
    source venv/bin/activate
    pip install --upgrade flask flask-login flask-limiter bcrypt gunicorn
    systemctl restart nova-xtunnel-panel
    echo -e "${GREEN}✅ Update complete!${NC}"
    exit 0
fi

# Web Server Selection
echo -e "\n${YELLOW}🌐 Web Server Configuration:${NC}"
echo -e "  ${GREEN}[1]${NC} Gunicorn only (HTTP)"
echo -e "  ${GREEN}[2]${NC} Gunicorn + SSL/HTTPS (Requires domain)"
echo ""
read -p "👉 Choose web server [1]: " server_choice
server_choice=${server_choice:-1}

case $server_choice in
    1)
        PANEL_SSL="false"
        echo -e "${GREEN}✅ Gunicorn HTTP mode selected${NC}"
        ;;
    2)
        PANEL_SSL="true"
        echo -e "${GREEN}✅ Gunicorn HTTPS mode selected${NC}"
        read -p "👉 Enter your domain name: " PANEL_DOMAIN
        if [[ -z "$PANEL_DOMAIN" ]]; then
            echo -e "${RED}❌ Domain name required for SSL${NC}"
            exit 1
        fi
        ;;
esac

# Port Configuration
echo -e "\n${YELLOW}🔌 Port Configuration:${NC}"

if [[ "$PANEL_SSL" == "true" ]]; then
    DEFAULT_PORT="443"
    echo -e "${CYAN}ℹ️ HTTPS mode will use port 443${NC}"
    read -p "👉 HTTPS port [443]: " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-443}
else
    DEFAULT_PORT="8080"
    echo -e "${CYAN}ℹ️ HTTP mode - direct access to Gunicorn${NC}"
    read -p "👉 Panel port [8080]: " PANEL_PORT
    PANEL_PORT=${PANEL_PORT:-8080}
fi

# Validate port
if ! [[ "$PANEL_PORT" =~ ^[0-9]+$ ]] || [ "$PANEL_PORT" -lt 1 ] || [ "$PANEL_PORT" -gt 65535 ]; then
    echo -e "${RED}❌ Invalid port number${NC}"
    exit 1
fi

if ! check_port $PANEL_PORT; then
    echo -e "${YELLOW}⚠️ Port $PANEL_PORT is in use${NC}"
    AVAILABLE_PORT=$(get_available_port $((PANEL_PORT + 1)))
    read -p "👉 Use alternative port $AVAILABLE_PORT? (y/n): " use_alt
    if [[ "$use_alt" == "y" || "$use_alt" == "Y" ]]; then
        PANEL_PORT=$AVAILABLE_PORT
        echo -e "${GREEN}✅ Using port $PANEL_PORT${NC}"
    else
        echo -e "${RED}❌ Please free port $PANEL_PORT and try again${NC}"
        exit 1
    fi
fi

# Admin credentials
echo -e "\n${YELLOW}👤 Admin Account Setup:${NC}"
read -p "👉 Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

read -p "👉 Admin password (leave empty for auto-generate): " ADMIN_PASS_INPUT
if [[ -z "$ADMIN_PASS_INPUT" ]]; then
    ADMIN_PASS=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 12)
    echo -e "${GREEN}🔑 Auto-generated password: ${YELLOW}$ADMIN_PASS${NC}"
else
    ADMIN_PASS="$ADMIN_PASS_INPUT"
fi

# Summary
echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                    INSTALLATION SUMMARY                       ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}  Configuration:${NC}"
echo -e "    • Version: ${GREEN}${VERSION}${NC}"
echo -e "    • Mode: Gunicorn"
echo -e "    • Panel Port: ${GREEN}$PANEL_PORT${NC}"
echo -e "    • SSL: $([[ "$PANEL_SSL" == "true" ]] && echo "${GREEN}Enabled${NC}" || echo "${RED}Disabled${NC}")"
[[ -n "$PANEL_DOMAIN" ]] && echo -e "    • Domain: ${GREEN}$PANEL_DOMAIN${NC}"
echo -e "    • Admin: ${GREEN}$ADMIN_USER${NC}"
echo -e ""
read -p "👉 Proceed with installation? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${RED}Installation cancelled${NC}"
    exit 0
fi

# Install dependencies
echo -e "\n${BLUE}📦 Installing dependencies...${NC}"
apt-get update
apt-get install -y python3 python3-pip python3-venv sqlite3 ufw curl wget git certbot

# Create panel directory
echo -e "${BLUE}📁 Creating directory structure...${NC}"
mkdir -p $PANEL_DIR/static/css
mkdir -p $PANEL_DIR/static/js
mkdir -p $PANEL_DIR/templates
mkdir -p $PANEL_DIR/utils
mkdir -p /var/log/nova-xtunnel-panel

# Download files
echo -e "${BLUE}📥 Downloading source files...${NC}"
curl -sSL "${REPO_URL}/src/app.py" -o $PANEL_DIR/app.py
curl -sSL "${REPO_URL}/src/init_db.py" -o $PANEL_DIR/init_db.py
curl -sSL "${REPO_URL}/src/gunicorn_config.py" -o $PANEL_DIR/gunicorn_config.py

curl -sSL "${REPO_URL}/src/utils/__init__.py" -o $PANEL_DIR/utils/__init__.py
curl -sSL "${REPO_URL}/src/utils/bandwidth.py" -o $PANEL_DIR/utils/bandwidth.py
curl -sSL "${REPO_URL}/src/utils/ssh_manager.py" -o $PANEL_DIR/utils/ssh_manager.py
curl -sSL "${REPO_URL}/src/utils/validators.py" -o $PANEL_DIR/utils/validators.py

curl -sSL "${REPO_URL}/src/templates/login.html" -o $PANEL_DIR/templates/login.html
curl -sSL "${REPO_URL}/src/templates/admin_dashboard.html" -o $PANEL_DIR/templates/admin_dashboard.html
curl -sSL "${REPO_URL}/src/templates/reseller_dashboard.html" -o $PANEL_DIR/templates/reseller_dashboard.html
curl -sSL "${REPO_URL}/src/templates/account_info.html" -o $PANEL_DIR/templates/account_info.html
curl -sSL "${REPO_URL}/src/templates/admin_resellers.html" -o $PANEL_DIR/templates/admin_resellers.html
curl -sSL "${REPO_URL}/src/templates/admin_zivpn.html" -o $PANEL_DIR/templates/admin_zivpn.html

curl -sSL "${REPO_URL}/src/static/css/style.css" -o $PANEL_DIR/static/css/style.css
curl -sSL "${REPO_URL}/src/static/js/dashboard.js" -o $PANEL_DIR/static/js/dashboard.js

# Create virtual environment
echo -e "${BLUE}🐍 Creating Python virtual environment...${NC}"
python3 -m venv $PANEL_DIR/venv
source $PANEL_DIR/venv/bin/activate
pip install --upgrade pip
pip install -r <(curl -sSL "${REPO_URL}/requirements.txt")

# Initialize database
echo -e "${BLUE}🗄️ Initializing database...${NC}"
python3 $PANEL_DIR/init_db.py "$ADMIN_USER" "$ADMIN_PASS"

# SSL Certificate (Standalone)
if [[ "$PANEL_SSL" == "true" ]]; then
    echo -e "${BLUE}🔒 Generating SSL certificate (standalone)...${NC}"
    systemctl stop nova-xtunnel-panel 2>/dev/null || true

    certbot certonly --standalone \
        -d "$PANEL_DOMAIN" \
        --non-interactive --agree-tos \
        --email "admin@$PANEL_DOMAIN"

    SSL_CERT="/etc/letsencrypt/live/$PANEL_DOMAIN/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/$PANEL_DOMAIN/privkey.pem"

    if [[ ! -f "$SSL_CERT" ]]; then
        echo -e "${RED}❌ SSL generation failed${NC}"
        exit 1
    fi
fi

# Update gunicorn config with port
sed -i "s/bind = .*/bind = \"0.0.0.0:${PANEL_PORT}\"/" $PANEL_DIR/gunicorn_config.py

# Create systemd service
echo -e "${BLUE}⚙️ Creating systemd service...${NC}"
cat > /etc/systemd/system/nova-xtunnel-panel.service << EOF
[Unit]
Description=NOVA-XTUNNEL Web Panel v${VERSION}
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$PANEL_DIR
Environment="PATH=$PANEL_DIR/venv/bin"
ExecStart=$PANEL_DIR/venv/bin/gunicorn \
    $([[ "$PANEL_SSL" == "true" ]] && echo "--certfile=$SSL_CERT --keyfile=$SSL_KEY") \
    -c $PANEL_DIR/gunicorn_config.py app:app
Restart=always
RestartSec=3
StandardOutput=append:/var/log/nova-xtunnel-panel/access.log
StandardError=append:/var/log/nova-xtunnel-panel/error.log

[Install]
WantedBy=multi-user.target
EOF

# Firewall
if command -v ufw &> /dev/null; then
    echo -e "${BLUE}🔥 Configuring firewall...${NC}"
    ufw allow $PANEL_PORT/tcp
    ufw reload
fi

# Start services
echo -e "${BLUE}🚀 Starting services...${NC}"
systemctl daemon-reload
systemctl enable nova-xtunnel-panel
systemctl restart nova-xtunnel-panel

sleep 3

if systemctl is-active --quiet nova-xtunnel-panel; then
    echo -e "${GREEN}✅ Panel service is running${NC}"
else
    echo -e "${RED}❌ Panel service failed to start${NC}"
    journalctl -u nova-xtunnel-panel -n 20 --no-pager
fi

# Final output
echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              INSTALLATION COMPLETED SUCCESSFULLY!            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}📊 Panel Access:${NC}"
if [[ "$PANEL_SSL" == "true" ]]; then
    echo -e "  ${GREEN}🔗 https://${PANEL_DOMAIN}${NC}"
else
    SERVER_IP=$(curl -s -4 icanhazip.com)
    echo -e "  ${GREEN}🔗 http://${SERVER_IP}:${PANEL_PORT}${NC}"
fi

echo -e "\n${YELLOW}🔑 Admin Credentials:${NC}"
echo -e "  Username: ${GREEN}$ADMIN_USER${NC}"
echo -e "  Password: ${GREEN}$ADMIN_PASS${NC}"
