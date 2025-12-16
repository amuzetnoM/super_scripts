#!/bin/bash

# ODUS System Dashboard
clear

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}"
cat << 'BANNER'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗                ║
║   ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝                ║
║   ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗                ║
║   ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║                ║
║   ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║                ║
║   ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝                ║
║                                                               ║
║        Next-Gen Autonomous Intelligence System               ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
BANNER
echo -e "${NC}"

# System Info
echo -e "${GREEN}═══ SYSTEM STATUS ═══${NC}"
UPTIME=$(uptime -p | sed 's/up //')
echo -e "Uptime: ${CYAN}$UPTIME${NC}"
echo -e "Hostname: ${CYAN}$(hostname)${NC}"
echo -e "Kernel: ${CYAN}$(uname -r)${NC}"
echo ""

# CPU
echo -e "${GREEN}═══ CPU USAGE ═══${NC}"
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
echo -e "CPU: ${CYAN}${CPU_USAGE}%${NC}"
echo ""

# Memory
echo -e "${GREEN}═══ MEMORY ═══${NC}"
MEM_INFO=$(free -h | grep Mem)
MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
MEM_PERCENT=$(free | grep Mem | awk '{print int($3/$2 * 100)}')
echo -e "Memory: ${CYAN}${MEM_USED}${NC} / ${CYAN}${MEM_TOTAL}${NC} (${CYAN}${MEM_PERCENT}%${NC})"
echo ""

# Disk
echo -e "${GREEN}═══ DISK USAGE ═══${NC}"
df -h / | tail -1 | awk '{print "Root: '$CYAN'" $3 "'$NC' / '$CYAN'" $2 "'$NC' ('$CYAN'" $5 "'$NC')"}'
echo ""

# Services Status
echo -e "${GREEN}═══ ODUS SERVICES ═══${NC}"
check_service() {
    if systemctl is-active --quiet "$1"; then
        echo -e "${GREEN}✓${NC} $2: ${GREEN}Active${NC}"
    else
        echo -e "${RED}✗${NC} $2: ${RED}Inactive${NC}"
    fi
}

check_service "odus-intelligence.timer" "Intelligence Engine"
check_service "odus-autoupdate.timer" "Auto-Update"
check_service "odus-selfheal.timer" "Self-Healing"
check_service "odus-cleanup-weekly.timer" "Weekly Cleanup"
check_service "odus-cleanup-biweekly.timer" "Bi-Weekly Cleanup"
echo ""

# Intelligence Summary
    if [ -f /etc/odus/intelligence.json ]; then
    echo -e "${GREEN}═══ INTELLIGENCE SUMMARY ═══${NC}"
    LAST_ANALYSIS=$(jq -r '.last_analysis.timestamp // "Never"' /etc/odus/intelligence.json 2>/dev/null)
    ISSUES=$(jq -r '.last_analysis.issues | length' /etc/odus/intelligence.json 2>/dev/null)
    SUGGESTIONS=$(jq -r '.last_analysis.suggestions | length' /etc/odus/intelligence.json 2>/dev/null)
    
    echo -e "Last Analysis: ${CYAN}${LAST_ANALYSIS}${NC}"
    echo -e "Active Issues: ${CYAN}${ISSUES}${NC}"
    echo -e "Suggestions: ${CYAN}${SUGGESTIONS}${NC}"
    echo ""
fi

# Recent Logs
echo -e "${GREEN}═══ RECENT ACTIVITY ═══${NC}"
if [ -f /var/log/odus/selfheal.log ]; then
    echo "Last Self-Healing:"
    tail -3 /var/log/odus/selfheal.log | sed 's/^/  /'
fi
echo ""

echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
echo -e "Run ${GREEN}odus-intelligence${NC} for detailed analysis"
echo -e "Run ${GREEN}odus-heal${NC} to trigger manual healing"
echo -e "Run ${GREEN}odus-cleanup${NC} for manual cleanup"
