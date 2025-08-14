#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Coder PM2 PaaS Health Check ===${NC}"
echo "Timestamp: $(date)"
echo

echo -e "${YELLOW}PostgreSQL 17 Status:${NC}"
if pgrep -f "postgres.*5432" > /dev/null; then
    echo -e "  ${GREEN}✅ PostgreSQL 17 is running${NC}"
    # Check if we can connect
    if sudo -u postgres /usr/lib/postgresql/17/bin/psql -lqt > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ PostgreSQL 17 is accepting connections${NC}"
    else
        echo -e "  ${YELLOW}⚠️  PostgreSQL 17 is running but not accepting connections${NC}"
    fi
else
    echo -e "  ${RED}❌ PostgreSQL 17 is not running${NC}"
fi

echo -e "${YELLOW}PGAdmin Status:${NC}"
if pgrep -f "pgadmin4" > /dev/null; then
    echo -e "  ${GREEN}✅ PGAdmin4 is running${NC}"
    if curl -s http://localhost:5050 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ PGAdmin4 is responding on port 5050${NC}"
    else
        echo -e "  ${YELLOW}⚠️  PGAdmin4 process running but not responding on port 5050${NC}"
    fi
else
    echo -e "  ${RED}❌ PGAdmin4 is not running${NC}"
fi

echo -e "${YELLOW}Admin App Status:${NC}"
if pgrep -f "node.*admin.*server.js" > /dev/null; then
    echo -e "  ${GREEN}✅ Admin application is running${NC}"
    if curl -s http://localhost:9000 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Admin application is responding on port 9000${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Admin application process running but not responding on port 9000${NC}"
    fi
else
    echo -e "  ${RED}❌ Admin application is not running${NC}"
fi

echo -e "${YELLOW}Documentation Server Status:${NC}"
if pgrep -f "python3.*8080" > /dev/null; then
    echo -e "  ${GREEN}✅ Documentation server is running${NC}"
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        echo -e "  ${GREEN}✅ Documentation server is responding on port 8080${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Documentation server process running but not responding on port 8080${NC}"
    fi
else
    echo -e "  ${RED}❌ Documentation server is not running${NC}"
fi

echo -e "${YELLOW}Slot Status:${NC}"
for i in {1..5}; do
    port=$((3000 + i))
    slot_letter=$(echo {a..e} | cut -d' ' -f$i)
    
    if pgrep -f "python3.*$port" > /dev/null || pgrep -f "node.*$port" > /dev/null; then
        echo -e "  ${GREEN}✅ Slot $slot_letter (port $port) is active${NC}"
        if curl -s http://localhost:$port > /dev/null 2>&1; then
            echo -e "    ${GREEN}✅ Responding to HTTP requests${NC}"
        else
            echo -e "    ${YELLOW}⚠️  Process running but not responding${NC}"
        fi
    else
        echo -e "  ${RED}❌ Slot $slot_letter (port $port) is not active${NC}"
    fi
done

echo
echo -e "${BLUE}Process Summary:${NC}"
echo -e "${YELLOW}Active Processes:${NC}"
ps aux | grep -E "(postgres|pgadmin4|node.*server|python3.*80[0-9][0-9]|python3.*30[0-9][0-9])" | grep -v grep | while read line; do
    echo "  $line"
done

echo
echo -e "${BLUE}Port Usage:${NC}"
if command -v netstat > /dev/null; then
    netstat -tlnp 2>/dev/null | grep -E ":(5432|5050|8080|9000|300[1-5])" | while read line; do
        echo "  $line"
    done
elif command -v ss > /dev/null; then
    ss -tlnp | grep -E ":(5432|5050|8080|9000|300[1-5])" | while read line; do
        echo "  $line"
    done
else
    echo -e "  ${YELLOW}⚠️  No netstat or ss command available for port checking${NC}"
fi

echo
echo -e "${BLUE}Available URLs:${NC}"
echo -e "  ${GREEN}📖 Documentation:${NC} \$CODER_ACCESS_URL or http://localhost:8080"
echo -e "  ${GREEN}⚙️  Admin Panel:${NC} https://admin--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:9000"
echo -e "  ${GREEN}🐘 PGAdmin:${NC} https://pgadmin--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:5050"
echo -e "  ${GREEN}🎰 Slot A:${NC} https://\${SLOT_A_SUBDOMAIN:-a}--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:3001"
echo -e "  ${GREEN}🎰 Slot B:${NC} https://\${SLOT_B_SUBDOMAIN:-b}--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:3002"
echo -e "  ${GREEN}🎰 Slot C:${NC} https://\${SLOT_C_SUBDOMAIN:-c}--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:3003"
echo -e "  ${GREEN}🎰 Slot D:${NC} https://\${SLOT_D_SUBDOMAIN:-d}--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:3004"
echo -e "  ${GREEN}🎰 Slot E:${NC} https://\${SLOT_E_SUBDOMAIN:-e}--main--\${CODER_WORKSPACE_NAME,,}--\${CODER_WORKSPACE_OWNER}.${ixd_domain:-ixdcoder.com}/ or http://localhost:3005"

echo
echo -e "${BLUE}System Information:${NC}"
echo -e "  ${YELLOW}Uptime:${NC} $(uptime)"
echo -e "  ${YELLOW}Memory Usage:${NC} $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo -e "  ${YELLOW}Disk Usage:${NC} $(df -h /home/coder | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"

if [ -d "/home/coder/data/pids" ]; then
    echo
    echo -e "${BLUE}PID Files:${NC}"
    ls -la /home/coder/data/pids/ 2>/dev/null | tail -n +2 | while read line; do
        echo "  $line"
    done
fi
