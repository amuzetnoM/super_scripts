#!/bin/bash
#═══════════════════════════════════════════════════════════════════════════════
# ODUS: Next-Gen Autonomous System
# Self-Installing | Self-Healing | Self-Optimizing | Self-Aware
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
# If running from the repo, prefer the local bundle; otherwise fall back to system path
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$SCRIPT_DIR/scripts" ]; then
    ODUS_HOME="$SCRIPT_DIR"
else
    ODUS_HOME="/opt/odus"
fi
ODUS_CONFIG="$ODUS_HOME/config"
ODUS_LOGS="$ODUS_HOME/logs"
ODUS_BACKUP_DIR="$ODUS_HOME/backups"
# Prefer the invoking user's home when run via sudo
if [ -n "${SUDO_USER:-}" ]; then
    USER_HOME="/home/${SUDO_USER}"
else
    USER_HOME="$HOME"
fi
WORKSPACE="$USER_HOME/workspace"

# Logging function
log() {
    mkdir -p "$ODUS_LOGS"
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$ODUS_LOGS/install.log"
}

error() {
    mkdir -p "$ODUS_LOGS"
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[ERROR] $1" >> "$ODUS_LOGS/install.log"
}

warn() {
    mkdir -p "$ODUS_LOGS"
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $1" >> "$ODUS_LOGS/install.log"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Check if running as root for system operations
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root or with sudo"
        exit 1
    fi
}

# Install packages safely: try individual installs and warn if a package has no candidate
safe_apt_install() {
    pkgs=("$@")
    for p in "${pkgs[@]}"; do
        if apt-cache policy "$p" | grep -q "Candidate: (none)"; then
            warn "Package '$p' has no installation candidate - skipping"
            continue
        fi
        if ! apt-get install -y "$p" >/dev/null 2>&1; then
            warn "Failed to install $p - continuing"
        else
            log "Installed $p"
        fi
    done
}

# Enable and start services if they exist
safe_enable_start() {
    for svc in "$@"; do
        if systemctl list-unit-files | grep -q "^${svc}\.service"; then
            if systemctl enable "$svc" >/dev/null 2>&1; then
                log "Enabled $svc"
            else
                warn "Failed to enable $svc"
            fi
            if systemctl start "$svc" >/dev/null 2>&1; then
                log "Started $svc"
            else
                warn "Failed to start $svc"
            fi
        else
            warn "Service $svc not found - skipping enable/start"
        fi
    done
}

# Initialize directories
init_directories() {
    # create directories first so logging works immediately
    mkdir -p "$ODUS_HOME"/scripts "$ODUS_HOME"/intelligence "$ODUS_HOME"/backups "$ODUS_HOME"/quarantine
    mkdir -p "$ODUS_CONFIG"
    mkdir -p "$ODUS_LOGS"
    mkdir -p "$WORKSPACE"/recon "$WORKSPACE"/exploit "$WORKSPACE"/logs "$WORKSPACE"/tools "$WORKSPACE"/scripts "$WORKSPACE"/notes "$WORKSPACE"/intel
    mkdir -p "$ODUS_BACKUP_DIR"

    chmod 755 "$ODUS_HOME"
    chmod 700 "$ODUS_CONFIG"
    chmod 755 "$ODUS_LOGS"

    log "Initialized ODUS directory structure"
}

# Install base system optimization
install_base_optimization() {
    log "Installing base system optimization..."
    
    apt update -qq
    # Use safe installer to skip packages that may be missing in some repos
    safe_apt_install zram-tools thermald tlp tlp-rdw irqbalance iotop sysstat lm-sensors smartmontools preload cpufrequtils
    
    # Enable services (only if they exist)
    safe_enable_start preload thermald tlp irqbalance
    
    # Configure zswap (add flags to existing GRUB_CMDLINE_LINUX_DEFAULT)
    if ! grep -q "zswap.enabled=1" /etc/default/grub; then
        sed -i "s|GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 zswap.enabled=1 zswap.compressor=lz4 zswap.max_pool_percent=20\"|" /etc/default/grub || true
        if command -v update-grub >/dev/null 2>&1; then
            update-grub
        else
            warn "update-grub not available; please update bootloader manually"
        fi
    fi
    
    # Optimize swappiness
    cat > /etc/sysctl.d/99-odus-performance.conf << EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
net.core.netdev_max_backlog=5000
net.ipv4.tcp_fastopen=3
kernel.sched_migration_cost_ns=5000000
kernel.sched_autogroup_enabled=0
EOF
    
    sysctl -p /etc/sysctl.d/99-odus-performance.conf || true
    
    success "Base optimization installed"
}

# Install graphics optimization
install_graphics() {
    log "Installing graphics optimization..."
    
    # Graphics packages (install only if available)
    safe_apt_install va-driver-all vdpau-driver-all mesa-va-drivers mesa-utils intel-gpu-tools vulkan-tools
    
    # Detect GPU and install appropriate drivers
    if lspci | grep -i nvidia > /dev/null; then
        apt install -y nvidia-driver nvidia-cuda-toolkit
    elif lspci | grep -i amd > /dev/null; then
        apt install -y firmware-amd-graphics mesa-vulkan-drivers
    fi
    
    success "Graphics optimization installed"
}

# Install modern shell environment
install_shell_environment() {
    log "Installing modern shell environment..."
    
    safe_apt_install zsh fonts-powerline fonts-noto-color-emoji
    
    # Install Oh-My-Zsh for all users who want it
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    
    # Install Powerlevel10k
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k 2>/dev/null || true
    
    # Install plugins
    git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions 2>/dev/null || true
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting 2>/dev/null || true
    
    # Configure .zshrc
    if [ -f "$HOME/.zshrc" ]; then
        sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc"
        sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting docker kubectl sudo)/' "$HOME/.zshrc"
    fi
    
    success "Shell environment installed"
}

# Install modern CLI tools
install_modern_cli() {
    log "Installing modern CLI tools..."
    
    safe_apt_install bat exa fd-find ripgrep fzf htop btop ncdu tldr tmux jq yq parallel pv tree silversearcher-ag duf procs
    
    # Install alacritty or kitty (try alacritty first)
    safe_apt_install alacritty
    if ! command -v alacritty >/dev/null 2>&1; then
        safe_apt_install kitty
    fi
    
    success "Modern CLI tools installed"
}

# Install development environment
install_dev_environment() {
    log "Installing development environment..."
    
    safe_apt_install python3-pip python3-venv pipx git vim neovim build-essential cmake pkg-config libssl-dev
    
    # Install Node.js
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        safe_apt_install nodejs
    fi
    
    # Install Go
    if ! command -v go &> /dev/null; then
        GO_VERSION="1.21.5"
        wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
        tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"
        rm "go${GO_VERSION}.linux-amd64.tar.gz"
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> /etc/profile.d/odus.sh
    fi
    
    # Install Rust
    if ! command -v cargo &> /dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    
    # Install Docker
    safe_apt_install docker.io docker-compose
    if command -v docker >/dev/null 2>&1; then
        systemctl enable docker
        systemctl start docker
    else
        warn "Docker not installed or not available in repos"
    fi
    
    success "Development environment installed"
}

# Install security tools
install_security_tools() {
    log "Installing comprehensive security toolkit..."
    
    safe_apt_install nmap masscan gobuster ffuf burpsuite zaproxy sqlmap wpscan nikto dirb wfuzz wireshark tcpdump bettercap metasploit-framework exploitdb hashcat john hydra medusa crunch aircrack-ng reaver wifite ettercap-graphical responder impacket-scripts enum4linux smbclient ldap-utils
    
    # Initialize metasploit
    msfdb init 2>/dev/null || true
    
    # Install modern Go-based tools
    if command -v go &> /dev/null; then
        export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
        go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
        go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
        go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
        go install -v github.com/projectdiscovery/katana/cmd/katana@latest
        go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
        go install -v github.com/tomnomnom/waybackurls@latest
        go install -v github.com/tomnomnom/gf@latest
        go install -v github.com/tomnomnom/httprobe@latest
    fi
    
    success "Security tools installed"
}

#═══════════════════════════════════════════════════════════════════════════════
# AUTONOMOUS INTELLIGENCE SYSTEM
#═══════════════════════════════════════════════════════════════════════════════

create_intelligence_engine() {
    log "Creating ODUS Intelligence Engine..."

    cat > "$ODUS_HOME/scripts/odus-intelligence.py" << 'INTELLIGENCE_EOF'
#!/usr/bin/env python3
"""
ODUS Intelligence Engine - System Analysis & Optimization AI
"""

import os
import sys
import json
import subprocess
import psutil
import time
from datetime import datetime, timedelta
from pathlib import Path

class OdusIntelligence:
    def __init__(self):
        self.config_dir = Path("/etc/odus")
        self.log_dir = Path("/var/log/odus")
        self.intel_file = self.config_dir / "intelligence.json"
        self.history_file = self.config_dir / "performance_history.json"
        self.load_data()
    
    def load_data(self):
        """Load historical data and configurations"""
        if self.intel_file.exists():
            with open(self.intel_file) as f:
                self.intel = json.load(f)
        else:
            self.intel = {
                "baseline_performance": {},
                "anomalies": [],
                "optimizations": [],
                "learning_data": {}
            }
        
        if self.history_file.exists():
            with open(self.history_file) as f:
                self.history = json.load(f)
        else:
            self.history = {"snapshots": []}
    
    def save_data(self):
        """Persist intelligence data"""
        self.config_dir.mkdir(parents=True, exist_ok=True)
        with open(self.intel_file, 'w') as f:
            json.dump(self.intel, f, indent=2)
        with open(self.history_file, 'w') as f:
            json.dump(self.history, f, indent=2)
    
    def collect_system_metrics(self):
        """Collect comprehensive system metrics"""
        cpu_percent = psutil.cpu_percent(interval=1, percpu=True)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage('/')
        net = psutil.net_io_counters()
        
        metrics = {
            "timestamp": datetime.now().isoformat(),
            "cpu": {
                "average": sum(cpu_percent) / len(cpu_percent),
                "per_core": cpu_percent,
                "count": psutil.cpu_count()
                {
                    "action": "disk_cleanup",
                    "description": "Run comprehensive disk cleanup",
                    "command": str(Path(__file__).resolve().parent / 'odus-cleanup.sh') + ' deep',
                    "priority": "high"
                }
            },
            "disk": {
                "total": disk.total,
                "used": disk.used,
                "free": disk.free,
                "percent": disk.percent
            },
            "network": {
                "bytes_sent": net.bytes_sent,
                "bytes_recv": net.bytes_recv,
                "packets_sent": net.packets_sent,
                "packets_recv": net.packets_recv
            },
            "processes": len(psutil.pids()),
            "boot_time": psutil.boot_time()
        }
        
        return metrics
    
    def analyze_performance(self, metrics):
        """Analyze system performance and detect issues"""
        issues = []
        suggestions = []
        
        # CPU Analysis
        if metrics["cpu"]["average"] > 80:
            issues.append("High CPU usage detected")
            suggestions.append("Consider identifying CPU-intensive processes")
        
        # Memory Analysis
        if metrics["memory"]["percent"] > 85:
            issues.append("High memory usage detected")
            suggestions.append("Memory pressure detected - consider closing unused applications")
        
        # Disk Analysis
        if metrics["disk"]["percent"] > 90:
            issues.append("Disk space critically low")
            suggestions.append("Run cleanup operations immediately")
        elif metrics["disk"]["percent"] > 80:
            suggestions.append("Disk space getting low - schedule cleanup")
        
        # Temperature checks (if sensors available)
        try:
            temps = psutil.sensors_temperatures()
            if temps:
                for name, entries in temps.items():
                    for entry in entries:
                        if entry.current > 80:
                            issues.append(f"High temperature on {name}: {entry.current}°C")
                            suggestions.append("Check cooling system and clean dust filters")
        except:
            pass
        
        return issues, suggestions
    
    def generate_optimization_plan(self, metrics, issues):
        """Generate intelligent optimization recommendations"""
        optimizations = []
        
        # Based on historical patterns
        if self.history["snapshots"]:
            recent = self.history["snapshots"][-10:]
            avg_cpu = sum(s["cpu"]["average"] for s in recent) / len(recent)
            avg_mem = sum(s["memory"]["percent"] for s in recent) / len(recent)
            
            if avg_cpu > 70:
                optimizations.append({
                    "action": "optimize_cpu_governors",
                    "description": "Switch to performance CPU governor for high-load workloads",
                    "command": "cpufreq-set -g performance",
                    "priority": "high"
                })
            
            if avg_mem > 70:
                optimizations.append({
                    "action": "increase_swappiness",
                    "description": "Adjust swap behavior to free up RAM",
                    "command": "sysctl -w vm.swappiness=20",
                    "priority": "medium"
                })
        
        # Disk optimization
        if metrics["disk"]["percent"] > 70:
            optimizations.append({
                "action": "disk_cleanup",
                "description": "Run comprehensive disk cleanup",
                "command": str(Path(__file__).resolve().parent / 'odus-cleanup.sh') + ' deep',
                "priority": "high"
            })
        
        return optimizations
    
    def self_heal(self, issues):
        """Automatically fix common issues"""
        healing_actions = []
        
        for issue in issues:
            if "memory" in issue.lower():
                # Clear caches
                try:
                    subprocess.run(["sync"], check=True)
                    with open("/proc/sys/vm/drop_caches", "w") as f:
                        f.write("3\n")
                    healing_actions.append("Cleared system caches")
                except:
                    pass
            
            if "disk" in issue.lower() and "critically" in issue.lower():
                # Emergency cleanup
                try:
                    subprocess.run([str(Path(__file__).resolve().parent / 'odus-cleanup.sh'), 'emergency'], capture_output=True)
                    healing_actions.append("Performed emergency disk cleanup")
                except:
                    pass
        
        return healing_actions
    
    def run_analysis(self):
        """Main analysis routine"""
        print("ODUS Intelligence Engine - Analyzing System...")
        
        # Collect metrics
        metrics = self.collect_system_metrics()
        
        # Store in history
        self.history["snapshots"].append(metrics)
        if len(self.history["snapshots"]) > 1000:
            self.history["snapshots"] = self.history["snapshots"][-1000:]
        
        # Analyze
        issues, suggestions = self.analyze_performance(metrics)
        
        # Generate optimizations
        optimizations = self.generate_optimization_plan(metrics, issues)
        
        # Self-heal if needed
        healing_actions = self.self_heal(issues)
        
        # Store intelligence
        self.intel["last_analysis"] = {
            "timestamp": datetime.now().isoformat(),
            "issues": issues,
            "suggestions": suggestions,
            "optimizations": optimizations,
            "healing_actions": healing_actions
        }
        
        self.save_data()
        
        # Report
        print(f"\n📊 System Health Report - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"   CPU: {metrics['cpu']['average']:.1f}%")
        print(f"   Memory: {metrics['memory']['percent']:.1f}%")
        print(f"   Disk: {metrics['disk']['percent']:.1f}%")
        
        if issues:
            print(f"\n⚠️  Issues Detected ({len(issues)}):")
            for issue in issues:
                print(f"   • {issue}")
        
        if healing_actions:
            print(f"\n🔧 Auto-Healing Actions:")
            for action in healing_actions:
                print(f"   ✓ {action}")
        
        if suggestions:
            print(f"\n💡 Suggestions:")
            for suggestion in suggestions:
                print(f"   • {suggestion}")
        
        if optimizations:
            print(f"\n🚀 Optimization Opportunities:")
            for opt in optimizations:
                print(f"   • [{opt['priority'].upper()}] {opt['description']}")
        
        return metrics, issues, suggestions, optimizations

if __name__ == "__main__":
    engine = OdusIntelligence()
    engine.run_analysis()
INTELLIGENCE_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-intelligence.py"
    
    # Install Python dependencies
    pip3 install psutil --break-system-packages 2>/dev/null || pip3 install psutil
    
    success "Intelligence engine created"
}

#═══════════════════════════════════════════════════════════════════════════════
# AUTONOMOUS UPDATE SYSTEM
#═══════════════════════════════════════════════════════════════════════════════

create_auto_updater() {
    log "Creating autonomous update system..."
    
    cat > "$ODUS_HOME/scripts/odus-autoupdate.sh" << 'UPDATER_EOF'
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
if [ -f "$ODUS_HOME/scripts/odus-intelligence.py" ]; then
    "$ODUS_HOME/scripts/odus-intelligence.py"
fi
UPDATER_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-autoupdate.sh"
    success "Auto-updater created"
}

#═══════════════════════════════════════════════════════════════════════════════
# AUTONOMOUS CLEANUP SYSTEM
#═══════════════════════════════════════════════════════════════════════════════

create_cleanup_system() {
    log "Creating intelligent cleanup system..."
    
    cat > "$ODUS_HOME/scripts/odus-cleanup.sh" << 'CLEANUP_EOF'
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
CLEANUP_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-cleanup.sh"
    success "Cleanup system created"
}

#═══════════════════════════════════════════════════════════════════════════════
# SELF-HEALING SYSTEM
#═══════════════════════════════════════════════════════════════════════════════

create_self_healing() {
    log "Creating self-healing system..."
    
    cat > "$ODUS_HOME/scripts/odus-selfheal.sh" << 'HEAL_EOF'
#!/bin/bash

ODUS_LOGS="/var/log/odus"
LOG_FILE="$ODUS_LOGS/selfheal.log"
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUARANTINE="$BASE_DIR/quarantine"

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
    "$ODUS_HOME/scripts/odus-cleanup.sh" emergency
elif [ "$DISK_USAGE" -gt 80 ]; then
    log_heal "⚠️  High disk space: ${DISK_USAGE}% - running deep cleanup"
    "$ODUS_HOME/scripts/odus-cleanup.sh" deep
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
HEAL_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-selfheal.sh"
    success "Self-healing system created"
}

#═══════════════════════════════════════════════════════════════════════════════
# SYSTEMD SERVICES
#═══════════════════════════════════════════════════════════════════════════════

create_systemd_services() {
    log "Creating systemd services..."
    
    # Intelligence Service (runs every hour)
    cat > /etc/systemd/system/odus-intelligence.service << EOF
[Unit]
Description=ODUS Intelligence Engine
After=network.target

[Service]
Type=oneshot
ExecStart=${ODUS_HOME}/scripts/odus-intelligence.py
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/odus-intelligence.timer << 'EOF'
[Unit]
Description=ODUS Intelligence Engine Timer
Requires=odus-intelligence.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=1h
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # Auto-Update Service (runs daily at 3 AM)
    cat > /etc/systemd/system/odus-autoupdate.service << EOF
[Unit]
Description=ODUS Auto-Update System
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${ODUS_HOME}/scripts/odus-autoupdate.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/odus-autoupdate.timer << 'EOF'
[Unit]
Description=ODUS Auto-Update Timer
Requires=odus-autoupdate.service

[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # Self-Healing Service (runs every 30 minutes)
    cat > /etc/systemd/system/odus-selfheal.service << EOF
[Unit]
Description=ODUS Self-Healing System
After=network.target

[Service]
Type=oneshot
ExecStart=${ODUS_HOME}/scripts/odus-selfheal.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/odus-selfheal.timer << 'EOF'
[Unit]
Description=ODUS Self-Healing Timer
Requires=odus-selfheal.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=30min
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # Weekly Deep Cleanup (runs every Sunday at 2 AM)
    cat > /etc/systemd/system/odus-cleanup-weekly.service << EOF
[Unit]
Description=ODUS Weekly Deep Cleanup
After=network.target

[Service]
Type=oneshot
ExecStart=${ODUS_HOME}/scripts/odus-cleanup.sh deep
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/odus-cleanup-weekly.timer << 'EOF'
[Unit]
Description=ODUS Weekly Cleanup Timer
Requires=odus-cleanup-weekly.service

[Timer]
OnCalendar=Sun 02:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # Bi-Weekly Standard Cleanup (runs every other Wednesday at 1 AM)
    cat > /etc/systemd/system/odus-cleanup-biweekly.service << EOF
[Unit]
Description=ODUS Bi-Weekly Cleanup
After=network.target

[Service]
Type=oneshot
ExecStart=${ODUS_HOME}/scripts/odus-cleanup.sh standard
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/odus-cleanup-biweekly.timer << 'EOF'
[Unit]
Description=ODUS Bi-Weekly Cleanup Timer
Requires=odus-cleanup-biweekly.service

[Timer]
OnCalendar=Wed *-*-1,15 01:00
Persistent=true
AccuracySec=1min

[Install]
WantedBy=timers.target
EOF

    # Reload systemd
    systemctl daemon-reload
    
    # Enable all services
    systemctl enable odus-intelligence.timer
    systemctl enable odus-autoupdate.timer
    systemctl enable odus-selfheal.timer
    systemctl enable odus-cleanup-weekly.timer
    systemctl enable odus-cleanup-biweekly.timer
    
    # Start all services
    systemctl start odus-intelligence.timer
    systemctl start odus-autoupdate.timer
    systemctl start odus-selfheal.timer
    systemctl start odus-cleanup-weekly.timer
    systemctl start odus-cleanup-biweekly.timer
    
    success "Systemd services created and enabled"
}

#═══════════════════════════════════════════════════════════════════════════════
# MONITORING & DASHBOARD
#═══════════════════════════════════════════════════════════════════════════════

create_monitoring_dashboard() {
    log "Creating monitoring dashboard..."
    
    cat > "$ODUS_HOME/scripts/odus-dashboard.sh" << 'DASHBOARD_EOF'
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
DASHBOARD_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-dashboard.sh"

    # Create convenient aliases
    cat >> /etc/profile.d/odus.sh << 'EOF'
# ODUS Command Aliases
alias odus="sudo \"$ODUS_HOME/scripts/odus-dashboard.sh\""
alias odus-dashboard="sudo \"$ODUS_HOME/scripts/odus-dashboard.sh\""
alias odus-intelligence="sudo \"$ODUS_HOME/scripts/odus-intelligence.py\""
alias odus-heal="sudo \"$ODUS_HOME/scripts/odus-selfheal.sh\""
alias odus-update="sudo \"$ODUS_HOME/scripts/odus-autoupdate.sh\""
alias odus-cleanup="sudo \"$ODUS_HOME/scripts/odus-cleanup.sh\""
alias odus-status='sudo systemctl status odus-*.timer'
alias odus-logs='sudo journalctl -u "odus-*" -f'

export PATH="$PATH:$ODUS_HOME/scripts"
EOF
    
    success "Monitoring dashboard created"
}

#═══════════════════════════════════════════════════════════════════════════════
# ADVANCED FEATURES
#═══════════════════════════════════════════════════════════════════════════════

create_backup_system() {
    log "Creating intelligent backup system..."
    
    cat > "$ODUS_HOME/scripts/odus-backup.sh" << 'BACKUP_EOF'
#!/bin/bash
 
BACKUP_DIR="/var/backups/odus"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/odus_backup_$TIMESTAMP.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "Creating ODUS configuration backup..."

# Backup important configs
tar -czf "$BACKUP_FILE" \
    /etc/odus \
    "$(cd "$(dirname "$0")/.." && pwd)/intelligence" \
    /root/.zshrc \
    /root/.config 2>/dev/null || true

# Keep only last 10 backups
ls -t $BACKUP_DIR/odus_backup_*.tar.gz | tail -n +11 | xargs rm -f 2>/dev/null || true

echo "Backup completed: $BACKUP_FILE"
BACKUP_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-backup.sh"
    
    # Create backup service
    cat > /etc/systemd/system/odus-backup.service << EOF
[Unit]
Description=ODUS Configuration Backup
After=network.target

[Service]
Type=oneshot
ExecStart=${ODUS_HOME}/scripts/odus-backup.sh
StandardOutput=journal
StandardError=journal
EOF

    cat > /etc/systemd/system/odus-backup.timer << 'EOF'
[Unit]
Description=ODUS Backup Timer
Requires=odus-backup.service

[Timer]
OnCalendar=daily
OnCalendar=04:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable odus-backup.timer
    systemctl start odus-backup.timer
    
    success "Backup system created"
}

create_performance_tuner() {
    log "Creating adaptive performance tuner..."
    
    cat > "$ODUS_HOME/scripts/odus-tune.sh" << 'TUNE_EOF'
#!/bin/bash

# Detect system workload and tune accordingly
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | cut -d'.' -f1)
CPU_COUNT=$(nproc)

if [ "$LOAD" -gt "$((CPU_COUNT * 2))" ]; then
    # High load - switch to performance
    cpufreq-set -g performance 2>/dev/null || true
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        if [ -f "$cpu/cpufreq/scaling_governor" ]; then
            echo performance > "$cpu/cpufreq/scaling_governor" 2>/dev/null || true
        fi
    done
    echo "Switched to PERFORMANCE mode (high load detected)"
elif [ "$LOAD" -lt "$CPU_COUNT" ]; then
    # Low load - switch to powersave
    cpufreq-set -g powersave 2>/dev/null || true
    for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
        if [ -f "$cpu/cpufreq/scaling_governor" ]; then
            echo powersave > "$cpu/cpufreq/scaling_governor" 2>/dev/null || true
        fi
    done
    echo "Switched to POWERSAVE mode (low load detected)"
else
    # Medium load - use ondemand/schedutil
    cpufreq-set -g ondemand 2>/dev/null || cpufreq-set -g schedutil 2>/dev/null || true
    echo "Using adaptive governor"
fi
TUNE_EOF
    
    chmod +x "$ODUS_HOME/scripts/odus-tune.sh"
    success "Performance tuner created"
}

# Install performance and benchmarking tools
install_perf_tools() {
        log "Installing performance & benchmarking tools..."
        apt update -qq || true
        safe_apt_install linux-tools-common linux-tools-$(uname -r) perf fio stress-ng cpupower cgroup-tools lm-sensors hwloc flamegraph || true

        # Install FlameGraph if not present
        if [ ! -d "$ODUS_HOME/tools/FlameGraph" ]; then
                mkdir -p "$ODUS_HOME/tools"
                git clone https://github.com/brendangregg/FlameGraph.git "$ODUS_HOME/tools/FlameGraph" 2>/dev/null || true
        fi

        success "Performance tools installed"
}

# IRQ pin helper installer
create_irqpin_script() {
        log "Creating IRQ pinning helper script..."
        cat > /usr/local/sbin/odus-irqpin.sh << 'IRQ_EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$EUID" -ne 0 ]; then echo "Run as root"; exit 1; fi
usage() { cat <<EOF
Usage: $0 [-d DRIVER] [-r IRQ] [-m MASK] [-a auto]
    -d DRIVER  driver name (e.g. i915, ath10k_pci)
    -r IRQ     specific irq number
    -m MASK    hex affinity mask (e.g. 0xF for cpus 0-3)
    -a auto    auto distribute IRQs across physical cores
EOF }
while getopts "d:r:m:ah" opt; do
    case $opt in
        d) driver=$OPTARG;;
        r) irq=$OPTARG;;
        m) mask=$OPTARG;;
        a) auto=1;;
        h) usage; exit 0;;
    esac
done

if [ -n "${driver:-}" ]; then
    grep -E "^[[:space:]]*\d+:" /proc/interrupts | grep -i "${driver}" || echo "No IRQs for driver $driver found"
fi

if [ -n "${irq:-}" ]; then
    if [ -n "${mask:-}" ]; then
        echo "$mask" > /proc/irq/$irq/smp_affinity
        echo "Set IRQ $irq affinity to $mask"
    else
        cat /proc/irq/$irq/smp_affinity
    fi
fi

if [ -n "${auto:-}" ]; then
    # Simple round robin across physical cores
    physcores=( $(lscpu -p=CPU,CORE | grep -v '^#' | awk -F, '{print $2}' | awk '!seen[$0]++') )
    irqs=( $(grep -E "^[[:space:]]*\d+:" /proc/interrupts | awk -F: '{print $1}' | xargs) )
    idx=0
    for i in "${irqs[@]}"; do
        core=${physcores[$((idx % ${#physcores[@]}))]}
        cpu=$(lscpu -p=CPU,CORE | grep -v '^#' | awk -F, -v C=$core '$2==C{print $1; exit}')
        mask=$(printf "0x%X" $((1<<cpu)))
        echo $mask > /proc/irq/$i/smp_affinity
        echo "Set IRQ $i -> CPU $cpu mask $mask"
        idx=$((idx+1))
    done
fi
IRQ_EOF
        chmod +x /usr/local/sbin/odus-irqpin.sh
        success "IRQ pin helper created at /usr/local/sbin/odus-irqpin.sh"
}

# Apply aggressive performance tuning for benchmarking
apply_performance_tweaks() {
        log "Applying performance tweaks (governor=performance, turbo enabled where supported)"
        # Set governors
        for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
                if [ -f "$cpu/cpufreq/scaling_governor" ]; then
                        echo performance > "$cpu/cpufreq/scaling_governor" 2>/dev/null || true
                fi
        done

        # Enable turbo (intel_pstate)
        if [ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]; then
                echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo || true
        fi

        # Prefer high energy performance
        if [ -f /sys/devices/system/cpu/intel_pstate/energy_performance_preference ]; then
                echo performance > /sys/devices/system/cpu/intel_pstate/energy_performance_preference || true
        fi

        # Disable powercapping if possible (platform dependent)
        if command -v cpupower >/dev/null 2>&1; then
                cpupower frequency-set -g performance || true
        fi

        success "Performance tweaks applied (runtime). For persistent changes, consider updating GRUB cmdline and BIOS settings."
}

#═══════════════════════════════════════════════════════════════════════════════
# MAIN INSTALLATION
#═══════════════════════════════════════════════════════════════════════════════

main() {
    echo -e "${MAGENTA}"
    cat << 'BANNER'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║    ███╗   ██╗███████╗██╗  ██╗██╗   ██╗███████╗                   ║
║    ████╗  ██║██╔════╝╚██╗██╔╝██║   ██║██╔════╝                   ║
║    ██╔██╗ ██║█████╗   ╚███╔╝ ██║   ██║███████╗                   ║
║    ██║╚██╗██║██╔══╝   ██╔██╗ ██║   ██║╚════██║                   ║
║    ██║ ╚████║███████╗██╔╝ ██╗╚██████╔╝███████║                   ║
║    ╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝                   ║
║                                                                   ║
║         Next-Gen Autonomous Kali Linux System                    ║
║         Self-Installing | Self-Healing | Self-Aware              ║
║                                                                   ║
╔═══════════════════════════════════════════════════════════════════╝
BANNER
    echo -e "${NC}"
    
    check_root
    init_directories
    
    echo ""
    info "Starting ODUS installation..."
    info "This will transform your Kali into an autonomous, self-optimizing system"
    echo ""
    
    # Phase 1: Base System
    log "PHASE 1: BASE SYSTEM OPTIMIZATION"
    install_base_optimization
    install_graphics
    
    # Phase 2: Development Environment
    log "PHASE 2: DEVELOPMENT ENVIRONMENT"
    install_shell_environment
    install_modern_cli
    install_dev_environment
    # Performance tools and tuning
    install_perf_tools
    create_irqpin_script
    apply_performance_tweaks
    
    # Phase 3: Security Tools
    log "PHASE 3: SECURITY TOOLKIT"
    install_security_tools
    
    # Phase 4: Autonomous Systems
    log "PHASE 4: AUTONOMOUS INTELLIGENCE SYSTEMS"
    create_intelligence_engine
    create_auto_updater
    create_cleanup_system
    create_self_healing
    create_systemd_services
    
    # Phase 5: Monitoring & Advanced Features
    log "PHASE 5: MONITORING & ADVANCED FEATURES"
    create_monitoring_dashboard
    create_backup_system
    create_performance_tuner
    
    # Final configuration
    log "Applying final configurations..."
    
    # Install jq for JSON processing
    apt install -y jq
    
    # Run initial intelligence analysis
    "$ODUS_HOME/scripts/odus-intelligence.py" || true
    
    # Create welcome message
    cat > /etc/motd << 'MOTD_EOF'

╔═══════════════════════════════════════════════════════════════╗
║                    ODUS SYSTEM ACTIVE                         ║
║          Next-Gen Autonomous Kali Linux                       ║
╚═══════════════════════════════════════════════════════════════╝

Autonomous Systems Online:
    • Intelligence Engine (hourly analysis)
    • Auto-Update System (daily at 3 AM)
    • Self-Healing Monitor (every 30 minutes)
    • Weekly Deep Cleanup (Sundays at 2 AM)
    • Bi-Weekly Cleanup (1st & 15th at 1 AM)

📊 Quick Commands:
    • odus               - View system dashboard
    • odus-intelligence  - Run AI analysis
    • odus-heal          - Trigger self-healing
    • odus-cleanup       - Manual cleanup
    • odus-status        - Check service status
    • odus-logs          - View live logs

Type 'odus' to see your system dashboard.

MOTD_EOF
    
    echo ""
    success "══════════════════════════════════════════════════════════="
    success "ODUS Installation Complete!"
    success "══════════════════════════════════════════════════════════="
    echo ""
    info "Your system is now:"
    echo "  ✓ Self-optimizing with AI-powered intelligence"
    echo "  ✓ Self-healing with automatic issue detection"
    echo "  ✓ Self-updating with daily security updates"
    echo "  ✓ Self-cleaning with intelligent maintenance"
    echo ""
    warn "IMPORTANT: Reboot your system to apply all changes"
    echo ""
    info "After reboot, run: ${GREEN}odus${NC}"
    info "View logs: ${GREEN}odus-logs${NC}"
    echo ""
    success "Welcome to the future of autonomous hacking platforms!"
    echo ""
}

# Run main installation
main "$@"