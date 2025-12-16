#!/bin/bash

ODUS_LOGS="/var/log/odus"
LOG_FILE="$ODUS_LOGS/autoupdate.log"

log_update() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_update "Starting ODUS Auto-Update Process"

# Update package lists
apt update -qq 2>&1 | tee -a "$LOG_FILE"

# Check for security updates
SECURITY_UPDATES=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
if [ "$SECURITY_UPDATES" -gt 0 ]; then
    log_update "🔒 $SECURITY_UPDATES security updates available - applying immediately"
    apt upgrade -y -qq 2>&1 | tee -a "$LOG_FILE"
fi

# Update system packages (non-security)
UPGRADABLE=$(apt list --upgradable 2>/dev/null | wc -l)
if [ "$UPGRADABLE" -gt 1 ]; then
    log_update "📦 $UPGRADABLE packages can be upgraded"
    apt upgrade -y -qq 2>&1 | tee -a "$LOG_FILE"
fi

# Update Go-based tools
if command -v go &> /dev/null; then
    export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
    log_update "Updating Go-based security tools"
    
    go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest 2>&1 | tee -a "$LOG_FILE"
    go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest 2>&1 | tee -a "$LOG_FILE"
    go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest 2>&1 | tee -a "$LOG_FILE"
    
    # Update nuclei templates
    nuclei -update-templates -silent 2>&1 | tee -a "$LOG_FILE"
fi

# Update Metasploit
if command -v msfupdate &> /dev/null; then
    log_update "🎯 Updating Metasploit Framework"
    msfupdate 2>&1 | tee -a "$LOG_FILE"
fi

# Update Python packages
if [ -f /root/go/bin/nuclei ]; then
    log_update "🐍 Updating Python security packages"
    pip3 install --upgrade pip --break-system-packages 2>&1 | tee -a "$LOG_FILE"
fi

# Clean up
apt autoremove -y -qq 2>&1 | tee -a "$LOG_FILE"
apt autoclean -y -qq 2>&1 | tee -a "$LOG_FILE"

log_update "✅ Auto-update completed successfully"

# Run intelligence analysis after updates
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/odus-intelligence.py" ]; then
    "$SCRIPT_DIR/odus-intelligence.py"
fi
