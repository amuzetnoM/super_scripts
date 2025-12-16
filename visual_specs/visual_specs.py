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
    def _bytes(n):
        # human friendly bytes
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if n < 1024.0:
                return f"{n:3.1f}{unit}"
            n /= 1024.0
        return f"{n:.1f}PB"

    fig = plt.figure(constrained_layout=True, figsize=(14, 10))
    gs = fig.add_gridspec(3, 2, height_ratios=[1, 1, 1])

    ax_text = fig.add_subplot(gs[0, 0])      # textual overview
    ax_disk = fig.add_subplot(gs[0, 1])      # disk pie
    ax_cpu = fig.add_subplot(gs[1, 0])       # per-core bars
    ax_load = fig.add_subplot(gs[1, 1])      # loadavg + freq
    ax_top_cpu = fig.add_subplot(gs[2, 0])   # top CPU procs
    ax_top_mem = fig.add_subplot(gs[2, 1])   # top MEM procs

    # --- Textual summary ---
    ax_text.axis('off')
    lines = []
    lines.append(f"Platform: {info['platform']}")
    lines.append(f"Kernel: {info['uname'].get('release','-')} ({info['uname'].get('machine','-')})")
    lines.append(f"CPU: {info['cpu_count_physical'] or '-'}p / {info['cpu_count_logical']}l")
    fq = info.get('cpu_freq_mhz', {})
    if fq:
        lines.append(f"CPU Freq (MHz): cur={int(fq.get('current',0))} max={int(fq.get('max',0))} min={int(fq.get('min',0))}")
    lines.append(f"Load Avg (1m,5m,15m): {', '.join([str(round(x,2)) for x in (info.get('loadavg') or [])])}")
    mem = info.get('mem', {})
    lines.append(f"Memory: {mem.get('percent',0)}% used of {_bytes(mem.get('total',0))} (avail {_bytes(mem.get('available',0))})")
    swap = info.get('swap', {})
    if swap.get('total', 0):
        lines.append(f"Swap: {swap.get('percent',0)}% used of {_bytes(swap.get('total',0))} (used {_bytes(swap.get('used',0))})")
    disk = info.get('disk', {})
    lines.append(f"Disk (/): {disk.get('percent',0)}% used of {_bytes(disk.get('total',0))} (used {_bytes(disk.get('used',0))})")

    ax_text.text(0, 1, '\n'.join(lines), fontsize=9, va='top')

    # --- Disk pie ---
    used = disk.get('used', 0)
    free = disk.get('free', 0)
    sizes = [used, free]
    labels = [f"Used ({disk.get('percent',0)}%)", f"Free ({100-disk.get('percent',0)}%)"]
    wedges, texts, autotexts = ax_disk.pie(sizes, labels=labels, autopct='%1.0f%%', colors=['#ff6b6b','#4ecdc4'], startangle=140, pctdistance=0.75)
    for t in texts + autotexts:
        t.set_fontsize(8)
    ax_disk.set_title("/ (root) disk usage")

    # --- Per-core CPU bars ---
    per = info.get('percpu_percent', [])
    x = list(range(len(per)))
    cmap = plt.get_cmap('viridis')
    if per:
        norm = [min(1.0, p/100.0) for p in per]
        colors = [cmap(v) for v in norm]
    else:
        colors = '#1f77b4'
    bars = ax_cpu.bar(x, per, color=colors)
    ax_cpu.set_ylim(0, 100)
    ax_cpu.set_xlabel('CPU core')
    ax_cpu.set_ylabel('% util')
    ax_cpu.set_title('Per-core CPU utilization')
    ax_cpu.grid(axis='y', linestyle=':', alpha=0.5)
    # annotate
    for i, b in enumerate(bars):
        h = b.get_height()
        ax_cpu.annotate(f"{h:.0f}%", xy=(b.get_x() + b.get_width() / 2, h), xytext=(0, 3), textcoords='offset points', ha='center', va='bottom', fontsize=8)

    # --- Loadavg and CPU freq ---
    load = info.get('loadavg') or []
    ax_load.axis('off')
    la = ', '.join([str(round(x,2)) for x in load]) if load else '-'
    freq = info.get('cpu_freq_mhz', {})
    freq_txt = f"CPU Freq (MHz): cur={int(freq.get('current',0))} max={int(freq.get('max',0))}"
    ax_load.text(0, 1, f"Load Avg (1m,5m,15m): {la}\n{freq_txt}", fontsize=9, va='top')

    # --- Top processes by CPU ---
    top = info.get('top_cpu', [])
    names_cpu = [f"{p.get('name','?')} ({p.get('pid')})" for p in top]
    cpus = [p.get('cpu_percent', 0) for p in top]
    if not names_cpu:
        names_cpu = ['-']
        cpus = [0]
    y_pos = list(range(len(names_cpu)))
    bars_cpu = ax_top_cpu.barh(y_pos, cpus, color='#ffa600')
    ax_top_cpu.set_yticks(y_pos)
    ax_top_cpu.set_yticklabels(names_cpu, fontsize=8)
    ax_top_cpu.set_xlabel('% CPU')
    ax_top_cpu.set_title('Top processes by CPU')
    for i, b in enumerate(bars_cpu):
        ax_top_cpu.annotate(f"{b.get_width():.1f}%", xy=(b.get_width(), b.get_y() + b.get_height() / 2), xytext=(3, 0), textcoords='offset points', va='center', fontsize=8)

    # --- Top processes by Memory ---
    topm = info.get('top_mem', [])
    names_mem = [f"{p.get('name','?')} ({p.get('pid')})" for p in topm]
    mems = [p.get('memory_percent', 0) for p in topm]
    if not names_mem:
        names_mem = ['-']
        mems = [0]
    y_pos_m = list(range(len(names_mem)))
    bars_mem = ax_top_mem.barh(y_pos_m, mems, color='#1f77b4')
    ax_top_mem.set_yticks(y_pos_m)
    ax_top_mem.set_yticklabels(names_mem, fontsize=8)
    ax_top_mem.set_xlabel('% Memory')
    ax_top_mem.set_title('Top processes by Memory')
    for i, b in enumerate(bars_mem):
        ax_top_mem.annotate(f"{b.get_width():.1f}%", xy=(b.get_width(), b.get_y() + b.get_height() / 2), xytext=(3, 0), textcoords='offset points', va='center', fontsize=8)

    fig.suptitle(f"Visual System Snapshot - {info['timestamp']}", fontsize=14)
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
