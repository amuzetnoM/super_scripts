#!/bin/bash

ODUS_LOGS="/var/log/odus"
LOG_FILE="$ODUS_LOGS/cleanup.log"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUARANTINE="$BASE_DIR/quarantine"

# Configurable artifact cleanup whitelist
# Edit these variables to control which artifacts are removed by cleanup flows.
ARTIFACT_DIR="/home/adam/worxpace"
ARTIFACT_PATTERNS=(
    "benchmarks_*.tar.gz"
    "randread.*"
    "randwrite.*"
    "installed_packages*"
    "installed_packag*"  # tolerant match for truncated names
)
# Toggle removable artifacts and dry-run for safety
REMOVE_ARTIFACTS=true
DRY_RUN=false

# Basic logging helper (ensures log dir exists)
log_cleanup() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Operation mode and baseline space
MODE="${1:-standard}"
BEFORE_SIZE=$(df / | tail -1 | awk '{print $3}')



remove_artifacts() {
    if [ "$REMOVE_ARTIFACTS" != "true" ]; then
        log_cleanup "Artifact removal is disabled (REMOVE_ARTIFACTS!=true)"
        return 0
    fi

    if [ "$DRY_RUN" = "true" ]; then
        log_cleanup "DRY RUN: would remove artifacts in $ARTIFACT_DIR"
        for p in "${ARTIFACT_PATTERNS[@]}"; do
            echo "  would remove: $ARTIFACT_DIR/$p"
        done
        return 0
    fi

    # Remove files matching whitelist in the workspace root only
    for p in "${ARTIFACT_PATTERNS[@]}"; do
        find "$ARTIFACT_DIR" -maxdepth 1 -type f -name "$p" -exec rm -f {} + 2>/dev/null || true
    done
    log_cleanup "Removed benchmark and report artifacts from $ARTIFACT_DIR"
}

case "$MODE" in
    emergency)
        log_cleanup "⚠️  EMERGENCY CLEANUP MODE"
        # Aggressive cleanup for critical disk space situations
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
        
        # Clear old kernels - SKIPPED for safety (automatic kernel removal is risky).
        # If you want to remove old kernels, run the helper below manually after
        # rebooting into a newer kernel:
        #   # dpkg -l 'linux-image-*' | awk '/^ii/ {print $2}' | grep -v "$(uname -r)" | xargs sudo apt purge -y
        echo "Skipping automatic kernel removal for safety" >> "$LOG_FILE"
        # Clear package cache
        apt clean
        
        # Clear systemd journal (keep 7 days)
        journalctl --vacuum-time=7d
        
        # Clear old logs
        find /var/log -type f -name "*.log" -mtime +30 -delete
        find /var/log -type f -name "*.gz" -mtime +30 -delete
        
        # Clear user caches
        find /home -type d -name ".cache" -exec rm -rf {}/* \\; 2>/dev/null || true
        
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

        # Remove benchmark and transient report artifacts (user workspace)
        # Use configurable whitelist (remove_artifacts uses ARTIFACT_PATTERNS/ARTIFACT_DIR)
        remove_artifacts

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
        
        # Remove benchmark and transient report artifacts (user workspace)
        # Use configurable whitelist (remove_artifacts uses ARTIFACT_PATTERNS/ARTIFACT_DIR)
        remove_artifacts

        log_cleanup "Standard cleanup completed"
        ;;
esac

# Calculate space freed
AFTER_SIZE=$(df / | tail -1 | awk '{print $3}')
FREED=$((BEFORE_SIZE - AFTER_SIZE))
FREED_MB=$((FREED / 1024))

log_cleanup "✅ Cleanup completed - Freed: ${FREED_MB}MB"

# Update system intelligence
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/odus-intelligence.py" ]; then
    "$SCRIPT_DIR/odus-intelligence.py"
fi
