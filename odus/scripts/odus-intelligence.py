#!/usr/bin/env python3
"""ODUS Intelligence Engine - System Analysis & Optimization

This script collects host metrics, keeps a short performance history, reports
issues, proposes optimizations and performs conservative self-heal actions.
"""

import json
import subprocess
from datetime import datetime
from pathlib import Path

import psutil


class OdusIntelligence:
    def __init__(self) -> None:
        self.config_dir = Path("/etc/odus")
        self.log_dir = Path("/var/log/odus")
        self.intel_file = self.config_dir / "intelligence.json"
        self.history_file = self.config_dir / "performance_history.json"
        self.intel = {}
        self.history = {"snapshots": []}
        self.load_data()

    def load_data(self) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        if self.intel_file.exists():
            try:
                with open(self.intel_file) as f:
                    self.intel = json.load(f)
            except Exception:
                self.intel = {}
        if self.history_file.exists():
            try:
                with open(self.history_file) as f:
                    self.history = json.load(f)
            except Exception:
                self.history = {"snapshots": []}

    def save_data(self) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        with open(self.intel_file, "w") as f:
            json.dump(self.intel, f, indent=2)
        with open(self.history_file, "w") as f:
            json.dump(self.history, f, indent=2)

    def collect_system_metrics(self) -> dict:
        cpu_percent = psutil.cpu_percent(interval=1, percpu=True)
        mem = psutil.virtual_memory()
        disk = psutil.disk_usage("/")
        net = psutil.net_io_counters()
        metrics = {
            "timestamp": datetime.now().isoformat(),
            "cpu": {
                "average": (sum(cpu_percent) / len(cpu_percent)) if cpu_percent else 0.0,
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
                "percent": disk.percent,
            },
            "network": {
                "bytes_sent": net.bytes_sent,
                "bytes_recv": net.bytes_recv,
                "packets_sent": net.packets_sent,
                "packets_recv": net.packets_recv,
            },
            "processes": len(psutil.pids()),
            "boot_time": psutil.boot_time(),
        }
        return metrics

    def analyze_performance(self, metrics: dict) -> tuple[list, list]:
        issues = []
        suggestions = []

        # CPU
        if metrics["cpu"]["average"] > 80:
            issues.append("High CPU usage detected")
            suggestions.append("Investigate top CPU consumers")

        # Memory
        if metrics["memory"]["percent"] > 85:
            issues.append("High memory usage detected")
            suggestions.append("Consider closing unused applications or increase swap")

        # Disk
        if metrics["disk"]["percent"] > 90:
            issues.append("Disk space critically low")
            suggestions.append("Run cleanup operations immediately")
        elif metrics["disk"]["percent"] > 80:
            suggestions.append("Disk space getting low - schedule cleanup")

        # Temperatures
        try:
            temps = psutil.sensors_temperatures()
            for name, entries in temps.items():
                for entry in entries:
                    current = getattr(entry, "current", 0)
                    if current and current > 85:
                        issues.append(f"High temperature on {name}: {current}C")
                        suggestions.append("Check cooling and firmware")
        except Exception:
            pass

        return issues, suggestions

    def generate_optimization_plan(self, metrics: dict, issues: list) -> list:
        optimizations = []
        recent = self.history.get("snapshots", [])[-10:]
        if recent:
            avg_cpu = sum(s["cpu"]["average"] for s in recent) / len(recent)
            avg_mem = sum(s["memory"]["percent"] for s in recent) / len(recent)
            if avg_cpu > 70:
                optimizations.append(
                    {
                        "action": "optimize_cpu_governors",
                        "description": "Switch to performance governor for heavy workloads",
                        "command": "cpupower frequency-set -g performance",
                        "priority": "high",
                    }
                )
            if avg_mem > 70:
                optimizations.append(
                    {
                        "action": "increase_swappiness",
                        "description": "Adjust swappiness to favor free memory",
                        "command": "sysctl -w vm.swappiness=20",
                        "priority": "medium",
                    }
                )

        if metrics["disk"]["percent"] > 70:
            optimizations.append(
                {
                    "action": "disk_cleanup",
                    "description": "Run disk cleanup",
                    "command": "/opt/odus/scripts/odus-cleanup.sh deep",
                    "priority": "high",
                }
            )

        return optimizations

    def self_heal(self, issues: list) -> list:
        actions = []
        for issue in issues:
            if "memory" in issue.lower():
                try:
                    subprocess.run(["sync"], check=True)
                    with open("/proc/sys/vm/drop_caches", "w") as f:
                        f.write("3\n")
                    actions.append("Cleared system caches")
                except Exception:
                    pass
            if "disk" in issue.lower():
                try:
                    subprocess.run(["/opt/odus/scripts/odus-cleanup.sh", "emergency"], check=False)
                    actions.append("Performed emergency cleanup")
                except Exception:
                    pass
        return actions

    def run_analysis(self) -> None:
        print("ODUS Intelligence Engine - Analyzing System...")
        metrics = self.collect_system_metrics()
        self.history.setdefault("snapshots", []).append(metrics)
        if len(self.history["snapshots"]) > 1000:
            self.history["snapshots"] = self.history["snapshots"][-1000:]
        issues, suggestions = self.analyze_performance(metrics)
        optimizations = self.generate_optimization_plan(metrics, issues)
        healing = self.self_heal(issues)
        self.intel["last_analysis"] = {
            "timestamp": datetime.now().isoformat(),
            "issues": issues,
            "suggestions": suggestions,
            "optimizations": optimizations,
            "healing_actions": healing,
        }
        self.save_data()
        print("\nSystem Health Report -", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        print(f"  CPU: {metrics['cpu']['average']:.1f}%")
        print(f"  Memory: {metrics['memory']['percent']:.1f}%")
        print(f"  Disk: {metrics['disk']['percent']:.1f}%")
        if issues:
            print("\nIssues Detected:")
            for i in issues:
                print(" -", i)
        if healing:
            print("\nAuto-Healing Actions:")
            for h in healing:
                print(" -", h)
        if optimizations:
            print("\nOptimization Opportunities:")
            for o in optimizations:
                print(" -", o["description"])


if __name__ == "__main__":
    engine = OdusIntelligence()
    engine.run_analysis()
