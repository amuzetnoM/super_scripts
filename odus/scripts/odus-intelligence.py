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
                "count": psutil.cpu_count(logical=True),
            },
            "memory": {
                "total": mem.total,
                "used": mem.used,
                "percent": mem.percent,
                "available": mem.available,
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
