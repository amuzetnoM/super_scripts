#!/usr/bin/env bash
# ==============================================================================
# Automated System Maintenance Script
#
# This script performs the following actions:
# 1. Updates all system packages using apt.
# 2. Checks the health of the primary Docker container.
# 3. Records system health metrics (Disk, Memory, CPU Load).
# 4. Logs all output to /var/log/gemini_maintenance.log for later review.
# ==============================================================================

set -euo pipefail

# Defaults
LOG_FILE="/var/log/gemini_maintenance.log"
DOCKER_CONTAINER_NAME="ai_cockpit"
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -h, --help         Show this help message and exit
  --dry-run          Print actions without executing package upgrades
  --log-file PATH    Path to write log output (default: /var/log/gemini_maintenance.log)
  --container NAME   Docker container name to check (default: ai_cockpit)

This script updates packages (Debian/Ubuntu), checks a Docker container status,
and records basic system health metrics (disk, memory, load).
EOF
}

if [[ ${1:-} == "--help" ]] || [[ ${1:-} == "-h" ]]; then
    usage
    exit 0
fi

# Parse long options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1; shift;;
        --log-file)
            LOG_FILE="$2"; shift 2;;
        --container)
            DOCKER_CONTAINER_NAME="$2"; shift 2;;
        -h|--help)
            usage; exit 0;;
        --) shift; break;;
        -*) echo "Unknown option: $1"; usage; exit 2;;
        *) break;;
    esac
done

is_root() { [ "$(id -u)" -eq 0 ]; }

maybe_sudo() {
    if is_root; then
        "$@"
    else
        sudo "$@"
    fi
}

timestamp() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
    local level="$1"; shift
    local msg="$*"
    local line="[$(timestamp)] [$level] $msg"
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "$line"
    else
        echo "$line" | tee -a "$LOG_FILE"
    fi
}

rotate_log_if_needed() {
    if [ -f "$LOG_FILE" ]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || true)
        if [ -n "$size" ] && [ "$size" -gt $((5*1024*1024)) ]; then
            mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
        fi
    fi
}

trap_on_exit() {
    local rc=$?
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY-RUN completed (rc=$rc)"
    else
        log INFO "Maintenance script exited with code $rc"
    fi
}
trap trap_on_exit EXIT

rotate_log_if_needed

log INFO "Starting System Maintenance Run"

# --- 1. System Package Update ---
if command -v apt-get >/dev/null 2>&1; then
    log INFO "Detected apt-get; updating package lists"
    if [ "$DRY_RUN" -eq 1 ]; then
        log INFO "DRY-RUN: apt-get update && apt-get upgrade -y"
    else
        maybe_sudo apt-get update -y
        maybe_sudo apt-get upgrade -y
        log INFO "System upgrade complete"
    fi
else
    log WARNING "apt-get not found; skipping package update (non-Debian system?)"
fi

# --- 2. Application Health Check ---
log INFO "Checking status of Docker container: $DOCKER_CONTAINER_NAME"
if command -v docker >/dev/null 2>&1; then
    # Check if a container with the exact name is running
    if docker ps -q -f "name=^/${DOCKER_CONTAINER_NAME}$" | grep -q .; then
        log SUCCESS "Docker container '$DOCKER_CONTAINER_NAME' is running"
    else
        log WARNING "Docker container '$DOCKER_CONTAINER_NAME' is NOT running"
    fi
else
    log WARNING "docker command not available; skipping container health check"
fi

# --- 3. System Health Metrics ---
log INFO "Recording system health metrics"
log INFO "Disk Usage:"; df -h | sed 's/^/    /' | while IFS= read -r l; do log INFO "$l"; done
log INFO "Memory Usage:"; free -h | sed 's/^/    /' | while IFS= read -r l; do log INFO "$l"; done
log INFO "CPU Load:"; uptime | sed 's/^/    /' | while IFS= read -r l; do log INFO "$l"; done

log INFO "System Maintenance Run Finished"

