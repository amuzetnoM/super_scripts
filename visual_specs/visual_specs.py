#!/usr/bin/env python3
"""Visual Specs - generate a compact visual system-specs image and a small JSON summary.
Saves: visual_specs.png and visual_specs.json (in working directory or supplied --outdir)
"""
import argparse
import json
import os
import platform
import shutil
from datetime import datetime

import psutil
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import textwrap


def gather():
    info = {}
    info["timestamp"] = datetime.now().astimezone().isoformat()
    info["platform"] = platform.platform()
    uname = platform.uname()
    info["uname"] = {"sysname": uname.system, "node": uname.node, "release": uname.release, "version": uname.version, "machine": uname.machine}

    info["cpu_count_logical"] = psutil.cpu_count(logical=True)
    info["cpu_count_physical"] = psutil.cpu_count(logical=False)
    try:
        freq = psutil.cpu_freq()
        info["cpu_freq_mhz"] = freq._asdict() if freq else {}
    except Exception:
        info["cpu_freq_mhz"] = {}

    info["percpu_percent"] = psutil.cpu_percent(percpu=True, interval=1)
    try:
        info["loadavg"] = os.getloadavg()
    except Exception:
        info["loadavg"] = []

    mem = psutil.virtual_memory()._asdict()
    info["mem"] = {k: mem[k] for k in ("total", "available", "percent", "used") if k in mem}
    swap = psutil.swap_memory()._asdict()
    info["swap"] = {k: swap[k] for k in ("total", "used", "percent") if k in swap}

    du = shutil.disk_usage("/")
    info["disk"] = {"total": du.total, "used": du.used, "free": du.free, "percent": int(du.used * 100 / du.total)}

    procs = []
    for p in psutil.process_iter(["pid", "name", "username", "cpu_percent", "memory_percent"]):
        try:
            procs.append(p.info)
        except Exception:
            pass
    info["top_cpu"] = sorted(procs, key=lambda p: p.get("cpu_percent", 0), reverse=True)[:6]
    info["top_mem"] = sorted(procs, key=lambda p: p.get("memory_percent", 0), reverse=True)[:6]
    return info


def render(info, out_png, out_json):
    fig = plt.figure(constrained_layout=True, figsize=(12, 8))
    gs = fig.add_gridspec(2, 2)

    ax0 = fig.add_subplot(gs[0, 0])  # text summary
    ax1 = fig.add_subplot(gs[0, 1])  # disk pie
    ax2 = fig.add_subplot(gs[1, 0])  # per-core bars
    ax3 = fig.add_subplot(gs[1, 1])  # top procs

    ax0.axis("off")
    t = []
    t.append(f"Platform: {info['platform']}")
    t.append(f"Kernel: {info['uname'].get('release','-')} ({info['uname'].get('machine','-')})")
    t.append(f"CPU: {info['cpu_count_physical'] or '-'}p / {info['cpu_count_logical']}l")
    fq = info.get('cpu_freq_mhz', {})
    if fq:
        t.append(f"CPU Freq: {int(fq.get('current', fq.get('max',0)))} MHz")
    t.append(f"Memory Used: {info['mem'].get('percent',0)}% of {info['mem'].get('total',0)//(1024**3)} GB")
    t.append(f"Disk Used: {info['disk'].get('percent',0)}% of {info['disk'].get('total',0)//(1024**3)} GB")
    text = "\n".join(t)
    ax0.text(0, 1, textwrap.fill(text, 60), fontsize=10, va="top")

    used = info['disk']['used']
    free = info['disk']['free']
    ax1.pie([used, free], labels=[f"Used {info['disk']['percent']}%", "Free"], autopct="%1.0f%%", colors=["#ff6b6b", "#4ecdc4"])
    ax1.set_title("/ (root) disk usage")

    per = info['percpu_percent']
    ax2.bar(range(len(per)), per, color="#1f77b4")
    ax2.set_ylim(0, 100)
    ax2.set_xlabel("CPU core")
    ax2.set_ylabel("% util")
    ax2.set_title("Per-core CPU utilization")

    top = info['top_cpu']
    names = [f"{p.get('name','?')} ({p.get('pid')})" for p in top]
    cpus = [p.get('cpu_percent', 0) for p in top]
    if not names:
        names = ["-"]
        cpus = [0]
    ax3.barh(range(len(names)), cpus, color="#ffa600")
    ax3.set_yticks(range(len(names)))
    ax3.set_yticklabels(names, fontsize=8)
    ax3.set_xlabel("% CPU")
    ax3.set_title("Top processes by CPU")

    fig.suptitle(f"Visual System Snapshot - {info['timestamp']}", fontsize=12)
    fig.savefig(out_png, dpi=150)
    plt.close(fig)


def main():
    p = argparse.ArgumentParser(description="Generate visual system specs (PNG + JSON)")
    p.add_argument("--outdir", help="Directory to write outputs (default: current directory)", default=".")
    args = p.parse_args()

    outdir = os.path.abspath(args.outdir)
    os.makedirs(outdir, exist_ok=True)
    out_png = os.path.join(outdir, "visual_specs.png")
    out_json = os.path.join(outdir, "visual_specs.json")

    info = gather()
    with open(out_json, "w") as f:
        json.dump(info, f, indent=2)
    render(info, out_png, out_json)
    print(f"Wrote: {out_png}")
    print(f"Wrote: {out_json}")


if __name__ == "__main__":
    main()
