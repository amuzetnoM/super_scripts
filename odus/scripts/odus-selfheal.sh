#!/bin/bash

ODUS_LOGS="/var/log/odus"
LOG_FILE="$ODUS_LOGS/selfheal.log"
QUARANTINE="/opt/odus/quarantine"

log_heal() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_heal "ODUS Self-Healing System - Starting Health Check"

# Function to check and fix service
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        return 0
    else
        log_heal "⚠️  Service $service is down - attempting restart"
        systemctl restart "$service"
        sleep 2
        if systemctl is-active --quiet "$service"; then
            log_heal "✅ Service $service restored"
            return 0
        else
            log_heal "❌ Failed to restore service $service"
            return 1
        fi
    fi
}

# Check critical services
CRITICAL_SERVICES=("docker" "ssh" "postgresql")

for service in "${CRITICAL_SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "^$service.service"; then
        check_service "$service"
    fi
done

# Check disk space
DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    log_heal "⚠️  Critical disk space: ${DISK_USAGE}% - running emergency cleanup"
    /opt/odus/scripts/odus-cleanup.sh emergency
elif [ "$DISK_USAGE" -gt 80 ]; then
    log_heal "⚠️  High disk space: ${DISK_USAGE}% - running deep cleanup"
    /opt/odus/scripts/odus-cleanup.sh deep
fi

# Check memory pressure
MEM_USAGE=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
if [ "$MEM_USAGE" -gt 90 ]; then
    log_heal "⚠️  Critical memory usage: ${MEM_USAGE}% - clearing caches"
    sync
    echo 3 > /proc/sys/vm/drop_caches
    log_heal "✅ System caches cleared"
fi

# Check for broken packages
BROKEN=$(dpkg -l | grep -c "^..r")
if [ "$BROKEN" -gt 0 ]; then
    log_heal "⚠️  Found $BROKEN broken packages - attempting repair"
    dpkg --configure -a
    apt --fix-broken install -y
    log_heal "✅ Package repair completed"
fi

# Check temperature (if available)
if command -v sensors &> /dev/null; then
    TEMP=$(sensors | grep -i "core 0" | awk '{print $3}' | sed 's/+//;s/°C//' | cut -d. -f1)
    if [ ! -z "$TEMP" ] && [ "$TEMP" -gt 85 ]; then
        log_heal "🔥 High CPU temperature: ${TEMP}°C - investigating"
        # Could trigger fan controls or alert
    fi
fi

# Check network connectivity
if ! ping -c 1 8.8.8.8 &> /dev/null; then
    log_heal "⚠️  Network connectivity issue detected - attempting fixes"
    systemctl restart NetworkManager
    sleep 5
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_heal "✅ Network connectivity restored"
    else
        log_heal "❌ Network issue persists - manual intervention may be needed"
    fi
fi

# Check for zombie processes
ZOMBIES=$(ps aux | awk '{print $8}' | grep -c Z)
if [ "$ZOMBIES" -gt 10 ]; then
    log_heal "⚠️  Found $ZOMBIES zombie processes - cleaning up"
    ps aux | awk '{if ($8=="Z") print $2}' | xargs kill -9 2>/dev/null || true
fi

log_heal "✅ Self-healing check completed"

# Run intelligence analysis
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/odus-intelligence.py" ]; then
        "$SCRIPT_DIR/odus-intelligence.py"
    fi
