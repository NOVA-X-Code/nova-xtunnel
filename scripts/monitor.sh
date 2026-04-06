#!/bin/bash
# NOVA-XTUNNEL Web Panel Monitoring Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PANEL_DIR="/var/www/nova-xtunnel-panel"

echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}         NOVA-XTUNNEL Web Panel Monitor${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"

# Check panel service
echo -e "\n${YELLOW}📊 Panel Service Status:${NC}"
if systemctl is-active --quiet nova-xtunnel-panel; then
    echo -e "  ${GREEN}✅ Running${NC}"
else
    echo -e "  ${RED}❌ Stopped${NC}"
fi

# Check Nginx
if command -v nginx &> /dev/null; then
    echo -e "\n${YELLOW}🌐 Nginx Status:${NC}"
    if systemctl is-active --quiet nginx; then
        echo -e "  ${GREEN}✅ Running${NC}"
    else
        echo -e "  ${RED}❌ Stopped${NC}"
    fi
fi

# Check database
echo -e "\n${YELLOW}🗄️ Database Status:${NC}"
if [ -f "$PANEL_DIR/panel.db" ]; then
    DB_SIZE=$(du -h "$PANEL_DIR/panel.db" | cut -f1)
    echo -e "  ${GREEN}✅ Database exists (Size: $DB_SIZE)${NC}"

    # Check integrity
    if command -v sqlite3 &> /dev/null; then
        INTEGRITY=$(sqlite3 "$PANEL_DIR/panel.db" "PRAGMA integrity_check;" 2>/dev/null)
        if [[ "$INTEGRITY" == "ok" ]]; then
            echo -e "  ${GREEN}✅ Database integrity OK${NC}"
        else
            echo -e "  ${RED}❌ Database corruption detected${NC}"
        fi
    fi
else
    echo -e "  ${RED}❌ Database not found${NC}"
fi

# Check disk space
echo -e "\n${YELLOW}💾 Disk Space:${NC}"
df -h / | awk 'NR==2 {print "  Used: " $3 " / " $2 " (" $5 ")"}'

# Check memory
echo -e "\n${YELLOW}🧠 Memory Usage:${NC}"
free -h | awk '/^Mem:/ {print "  Used: " $3 " / " $2 " (" $3/$2*100 "%)"}'

# Check online users
echo -e "\n${YELLOW}👥 Online Users:${NC}"
if [ -f "$PANEL_DIR/panel.db" ]; then
    ONLINE_COUNT=$(sqlite3 "$PANEL_DIR/panel.db" "SELECT COUNT(*) FROM user_sessions WHERE datetime(started_at) > datetime('now', '-1 hour');" 2>/dev/null || echo "0")
    echo -e "  ${GREEN}Active sessions (last hour): $ONLINE_COUNT${NC}"
fi

# Check bandwidth usage
echo -e "\n${YELLOW}📈 Bandwidth Usage:${NC}"
if [ -d "/etc/nova-xtunnel/bandwidth" ]; then
    TOTAL_BW=0
    for file in /etc/nova-xtunnel/bandwidth/*.usage; do
        if [ -f "$file" ]; then
            BW=$(cat "$file" 2>/dev/null || echo 0)
            TOTAL_BW=$((TOTAL_BW + BW))
        fi
    done
    TOTAL_GB=$(echo "scale=2; $TOTAL_BW / 1073741824" | bc)
    echo -e "  ${GREEN}Total bandwidth used: ${TOTAL_GB} GB${NC}"
fi

# Check logs for errors
echo -e "\n${YELLOW}📋 Recent Errors:${NC}"
if [ -f "/var/log/nova-xtunnel-panel/error.log" ]; then
    ERRORS=$(tail -20 /var/log/nova-xtunnel-panel/error.log | grep -i error || echo "  No recent errors")
    echo -e "  ${GREEN}$ERRORS${NC}"
else
    echo -e "  ${YELLOW}No log file found${NC}"
fi

# Recommendations
echo -e "\n${YELLOW}💡 Recommendations:${NC}"

# Check if backup exists
if [ ! -f "/root/backups/nova-xtunnel/panel_backup_"*".db" 2>/dev/null ]; then
    echo -e "  ${YELLOW}⚠️  No backups found. Run backup script.${NC}"
fi

# Check if swap is enabled
if ! swapon --show | grep -q .; then
    echo -e "  ${YELLOW}⚠️  Swap not enabled. Consider adding swap for better performance.${NC}"
fi

# Check panel version
if [ -f "$PANEL_DIR/app.py" ]; then
    VERSION=$(grep -oP 'v\d+\.\d+\.\d+' "$PANEL_DIR/app.py" 2>/dev/null | head -1 || echo "Unknown")
    echo -e "  ${GREEN}Panel Version: $VERSION${NC}"
fi

echo -e "\n${GREEN}════════════════════════════════════════════════════════════${NC}"