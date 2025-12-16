#!/bin/bash

ODUS_LOGS="/var/log/odus"
LOG_FILE="$ODUS_LOGS/cleanup.log"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUARANTINE="$BASE_DIR/quarantine"

log_cleanup() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

MODE="${1:-standard}"

log_cleanup "Starting ODUS Cleanup - Mode: $MODE"

# Calculate sizes before cleanup
BEFORE_SIZE=$(df / | tail -1 | awk '{print $3}')

case "$MODE" in
    emergency)
        log_cleanup "⚠️  EMERGENCY CLEANUP MODE"
        # Aggressive cleanup for critical disk space situations
        
        # Clear all caches
        apt clean
        apt autoclean
        
        # Clear thumbnail cache
        rm -rf ~/.cache/thumbnails/*
        
        # Clear old logs (keep 3 days)
        find /var/log -type f -name "*.log" -mtime +3 -delete
        find /var/log -type f -name "*.gz" -delete
        
        # Clear temp files
        rm -rf /tmp/*
        rm -rf /var/tmp/*
        
        # Docker cleanup
        if command -v docker &> /dev/null; then
            docker system prune -af --volumes
        fi
        
        log_cleanup "Emergency cleanup completed"
        ;;
        
    deep)
        log_cleanup "🔍 DEEP CLEANUP MODE"
        
        # Standard cleanup
        apt autoremove -y
        apt autoclean -y
        apt clean
        
        # Clear old kernels (keep current and previous)
        dpkg -l 'linux-*' | sed '/^ii/!d;/'"$(uname -r | sed "s/\(.*\)-\([^0-9]\+\)/\1/")"'/d;s/^[^ ]* [^ ]* \([^ ]*\).*/\1/;/[0-9]/!d' | xargs apt purge -y 2>/dev/null || true
        
        # Clear package cache
        apt clean
        
        # Clear systemd journal (keep 7 days)
        journalctl --vacuum-time=7d
        
        # Clear old logs
        find /var/log -type f -name "*.log" -mtime +30 -delete
        find /var/log -type f -name "*.gz" -mtime +30 -delete
        
        # Clear user caches
        find /home -type d -name ".cache" -exec rm -rf {}/* \; 2>/dev/null || true
        
        # Clear thumbnail cache
        find /home -type d -name ".thumbnails" -exec rm -rf {}/* \; 2>/dev/null || true
        
        # Docker cleanup
        if command -v docker &> /dev/null; then
            docker system prune -a --volumes -f
        fi
        
        # Clear pip cache
        pip3 cache purge 2>/dev/null || true
        
        # Clear npm cache
        npm cache clean --force 2>/dev/null || true
        
        log_cleanup "Deep cleanup completed"
        ;;
        
    standard|*)
        log_cleanup "📦 STANDARD CLEANUP MODE"
        
        # Remove old packages
        apt autoremove -y
        apt autoclean -y
        
        # Clear package lists
        rm -rf /var/lib/apt/lists/*
        apt update -qq
        
        # Clear old journal entries (keep 14 days)
        journalctl --vacuum-time=14d
        
        # Clear old logs (keep 60 days)
        find /var/log -type f -name "*.log" -mtime +60 -delete
        find /var/log -type f -name "*.gz" -mtime +60 -delete
        
        # Clear temp files older than 7 days
        find /tmp -type f -atime +7 -delete 2>/dev/null || true
        find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
        
        # Docker cleanup (conservative)
        if command -v docker &> /dev/null; then
            docker system prune -f
        fi
        
        log_cleanup "Standard cleanup completed"
        ;;
esac

# Calculate space freed
AFTER_SIZE=$(df / | tail -1 | awk '{print $3}')
FREED=$((BEFORE_SIZE - AFTER_SIZE))
FREED_MB=$((FREED / 1024))

log_cleanup "✅ Cleanup completed - Freed: ${FREED_MB}MB"

# Update system intelligence
    if [ -f "$ODUS_HOME/scripts/odus-intelligence.py" ]; then
        "$ODUS_HOME/scripts/odus-intelligence.py"
    fi
