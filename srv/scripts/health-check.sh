#!/bin/bash

# this is a health check utitlity. 
# it is not called by other scripts but might be useful for debugging
# you can run it manually from the terminal inside the coder workspace



echo "=== NodeJS App Server Health Check ==="
echo "Timestamp: $(date)"
echo

echo "PostgreSQL 17 Status:"
if pgrep -f "postgres.*5432" > /dev/null; then
    echo "  ✅ PostgreSQL 17 is running"
    # Check if we can connect
    if sudo -u postgres /usr/lib/postgresql/17/bin/psql -lqt > /dev/null 2>&1; then
        echo "  ✅ PostgreSQL 17 is accepting connections"
    else
        echo "  ⚠️  PostgreSQL 17 is running but not accepting connections"
    fi
else
    echo "  ❌ PostgreSQL 17 is not running"
fi

echo "PGAdmin Status:"
if pgrep -f "pgadmin4" > /dev/null; then
    echo "  ✅ PGAdmin4 is running"
    if curl -s http://localhost:5050 > /dev/null 2>&1; then
        echo "  ✅ PGAdmin4 is responding on port 5050"
    else
        echo "  ⚠️  PGAdmin4 process running but not responding on port 5050"
    fi
else
    echo "  ❌ PGAdmin4 is not running"
fi

echo "Admin App Status (PM2):"
if pm2 describe admin-server >/dev/null 2>&1; then
    pm2_status=$(pm2 describe admin-server | grep -E '^\s*status\s*:' | awk '{print $3}' || echo "unknown")
    if [ "$pm2_status" = "online" ]; then
        echo "  ✅ Admin application is running (PM2: $pm2_status)"
        if curl -s http://localhost:9000 > /dev/null 2>&1; then
            echo "  ✅ Admin application is responding on port 9000"
        else
            echo "  ⚠️  Admin application running but not responding on port 9000"
        fi
    else
        echo "  ⚠️  Admin application PM2 status: $pm2_status"
    fi
else
    echo "  ❌ Admin application is not running (PM2 not found)"
fi

echo "Slot Status (PM2):"
for i in {1..5}; do
    port=$((3000 + i))
    slot_letter=$(echo {a..e} | cut -d' ' -f$i)
    slot_name="slot-$slot_letter"
    
    # Check PM2 process status
    if pm2 describe "$slot_name" >/dev/null 2>&1; then
        pm2_status=$(pm2 describe "$slot_name" | grep -E '^\s*status\s*:' | awk '{print $3}' || echo "unknown")
        if [ "$pm2_status" = "online" ]; then
            echo "  ✅ Slot $slot_letter is running (PM2: $pm2_status)"
            # Test HTTP response
            if curl -s "http://localhost:$port" > /dev/null 2>&1; then
                echo "    ✅ HTTP response on port $port"
            else
                echo "    ⚠️  No HTTP response on port $port"
            fi
        else
            echo "  ⚠️  Slot $slot_letter PM2 status: $pm2_status"
        fi
    else
        echo "  ❌ Slot $slot_letter (port $port) is not active"
    fi
done

echo
echo "PM2 Status Summary:"
if pm2 ping >/dev/null 2>&1; then
    echo "PM2 Daemon: ✅ Running"
    echo "PM2 Processes:"
    pm2 jlist | jq -r '.[] | "  \(.name): \(.pm2_env.status) (PID: \(.pid // "N/A"), Port: \(.pm2_env.PORT // "N/A"))"' 2>/dev/null || {
        # Fallback if jq is not available
        pm2 list --no-color | grep -E "^\s*│" | head -n -1 | tail -n +2 | while read line; do
            echo "  $line"
        done
    }
else
    echo "PM2 Daemon: ❌ Not running"
fi

echo
echo "Process Summary:"
echo "Active Processes:"
ps aux | grep -E "(postgres|pgadmin4|node.*server.js|python3.*30[0-9][0-9])" | grep -v grep | while read line; do
    echo "  $line"
done

echo
echo "Port Usage:"
if command -v netstat > /dev/null; then
    netstat -tlnp 2>/dev/null | grep -E ":(5432|5050|9000|300[1-5])" | while read line; do
        echo "  $line"
    done
elif command -v ss > /dev/null; then
    ss -tlnp | grep -E ":(5432|5050|9000|300[1-5])" | while read line; do
        echo "  $line"
    done
else
    echo "  ⚠️  No netstat or ss command available for port checking"
fi

echo
echo "Available URLs:"
echo "  ⚙️  Admin Panel: https://admin--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:9000"
echo "  🐘 PGAdmin: https://pgadmin--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:5050"
echo "  🎰 Slot A: https://${SLOT_A_SUBDOMAIN:-a}--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:3001"
echo "  🎰 Slot B: https://${SLOT_B_SUBDOMAIN:-b}--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:3002"
echo "  🎰 Slot C: https://${SLOT_C_SUBDOMAIN:-c}--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:3003"
echo "  🎰 Slot D: https://${SLOT_D_SUBDOMAIN:-d}--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:3004"
echo "  🎰 Slot E: https://${SLOT_E_SUBDOMAIN:-e}--main--${WORKSPACE_NAME,,}--${USERNAME}.${IXD_DOMAIN:-ixdcoder.com}/ or http://localhost:3005"

echo
echo "System Information:"
echo "  Uptime: $(uptime)"
echo "  Memory Usage: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
echo "  Disk Usage: $(df -h /home/coder | tail -1 | awk '{print $3 "/" $2 " (" $5 " used)"}')"

if [ -d "/home/coder/data/pids" ]; then
    echo
    echo "PID Files:"
    ls -la /home/coder/data/pids/ 2>/dev/null | tail -n +2 | while read line; do
        echo "  $line"
    done
fi
