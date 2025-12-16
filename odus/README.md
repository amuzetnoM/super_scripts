# ODUS System Manager

ODUS is a lightweight system management suite focused on performance, reliability and autopilot maintenance for single-host systems used for development, benchmarking and pentesting. It bundles:

- An **intelligence engine** that collects metrics, maintains baselines, and recommends or applies fixes
- **Automated maintenance** (autoupdate, cleanup, backup) driven by systemd timers
- **Self-heal** capability that restarts failed services and repairs common package issues
- **Benchmarking** utilities and reproducible recipes to baseline performance and track regressions
- Tools and scripts for **profiling** (FlameGraph) and **IRQ/cpu affinity** helpers

This README documents installation, services, timers, scripts, logs, troubleshooting and how ODUS keeps your system "blazingly fast".

---

## Quick start

1. Install/run the installer:

```bash
sudo chmod +x odus-install.sh
sudo ./odus-install.sh
```

2. Fix package state if interrupted (safe, idempotent):

```bash
sudo bash /home/adam/worxpace/odus_auto/run_odus_maintenance.sh
```

3. Run benchmarks (on-demand):

```bash
sudo bash /home/adam/worxpace/odus_auto/odus_benchmark.sh /home/adam/worxpace/benchmarks
```

4. Check ODUS status and logs:

```bash
systemctl status odus-intelligence.service odus-autoupdate.service odus-selfheal.service
journalctl -u odus-autoupdate -n 200
ls -l /var/log/odus
```

---

## Installed ODUS systemd units & timers

Unit files are installed under `/etc/systemd/system/`. Key units & timers on this host:

- `odus-intelligence.service` (+ `odus-intelligence.timer`) — runs `./scripts/odus-intelligence.py` (collects telemetry, writes intelligence summaries, may trigger actions)
- `odus-autoupdate.service` (+ `odus-autoupdate.timer`) — runs `./scripts/odus-autoupdate.sh` (applies updates; daily @ 03:00 by default)
- `odus-selfheal.service` (+ `odus-selfheal.timer`) — runs `./scripts/odus-selfheal.sh` (monitors and heals critical services)
- `odus-cleanup-weekly.service` / `odus-cleanup-biweekly.service` (+ timers) — garbage collection and adaptive cleanup
- `odus-backup.service` (+ `odus-backup.timer`) — rotate/save ODUS configuration snapshots

Example `odus-intelligence.service` unit (installed):

```
[Unit]
Description=ODUS Intelligence Engine
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/odus/scripts/odus-intelligence.py
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

And an example timer (`odus-autoupdate.timer`):

```
[Timer]
OnCalendar=daily
OnCalendar=03:00
Persistent=true
AccuracySec=1min
```

To inspect them:

```bash
sudo systemctl cat odus-intelligence.service
sudo systemctl list-timers --all | grep odus
```

---

## Scripts and tools (what each does)

All runtime scripts live in `./scripts` within this repo and helper tooling under `./tools` (if available).

- `./scripts/odus-intelligence.py` — metrics collector and simple rules engine. It gathers CPU, memory, disk, thermal sensors and compares to stored baselines in `./config/` to detect regressions and recommend fixes.
- `/opt/odus/scripts/odus-autoupdate.sh` — performs safe updates: apt update/upgrade, updates Go tools and Metasploit/nuclei signatures, but **skips** packages with no candidate (safe_apt_install) to avoid blocking.
- `/opt/odus/scripts/odus-selfheal.sh` — checks a list of critical services and restarts/alerts on failures, attempts package fixes (`dpkg --configure -a` / `apt --fix-broken install`) when necessary.
- `/opt/odus/scripts/odus-cleanup.sh` — adaptive cleanup (apt autoremove, journal rotation, orphaned temp), has `--deep` option for aggressive cleaning.
- `./scripts/odus-backup.sh` — snapshots ODUS configs and rotates last N backups under `./backups`.
- `/opt/odus/scripts/odus-dashboard.sh` — interactive ASCII dashboard showing top metrics and service health.
- `/opt/odus/scripts/odus-tune.sh` — applies conservative sysctl and CPU governor tweaks found under `/etc/sysctl.d/99-odus-performance.conf` and GRUB additions (zswap). For safety it logs changes and requires root.

Included tooling (optional): FlameGraph under `./tools/FlameGraph` for generating flamegraphs from `perf` output; useful for profiling hotspots.

---

## Logs & where to find actions

All ODUS logs are under `/var/log/odus`:

- `install.log` — installer output and traces
- `autoupdate.log` — auto-update runs and results
- `cleanup.log` — cleanup activity
- `selfheal.log` — self-heal actions and decisions

Check live unit logs with `journalctl -u <unit>`; check installer or script logs under `/var/log/odus` for historical runs.

---

## Benchmarks & baseline

Benchmarks are intentionally run on-demand and write a human- and machine-readable report under the directory you pass to the runner (recommended: `/home/adam/worxpace/benchmarks`).

Example:

```bash
sudo bash /home/adam/worxpace/odus_auto/odus_benchmark.sh /home/adam/worxpace/benchmarks
# Outputs:
# - /home/adam/worxpace/benchmarks/odus_benchmark_report.md
# - /home/adam/worxpace/benchmarks/odus_benchmark_report.json
```

Benchmarks are short CPU/memory/disk tests (sysbench and fio). `perf` counters are attempted (best-effort) if kernel-tools are available. If `linux-tools-<version>` or `perf` are missing, the script logs and continues.

---

## Performance tuning & "blazing fast" checklist

Mechanics used by ODUS to keep latency low and throughput high:

- **IRQ pinning helper** to move interrupts to dedicated cores (`/usr/local/sbin/irqpin.sh`)
- **Sysctl tweaks** applied in `/etc/sysctl.d/99-odus-performance.conf` (swappiness, vfs_cache_pressure, dirty thresholds) — review before enabling in production
- **Grub flags** updated for zswap (see `/etc/default/grub` for `zswap.enabled=1 zswap.compressor=lz4` additions)
- **CPU governor management** via `odus-tune.sh` (sets `performance` for benchmarking; respects systems without cpufreq tools)
- **Profiling tools**: FlameGraph and `perf` when available

Important safety note: ODUS will not remove the **running** kernel; if a package operation attempts to remove the current kernel, the dpkg prerm hook will abort and ODUS will log the condition — see Troubleshooting below.

---

## Troubleshooting & FAQs

Q: The installer got "stuck" during package updates — what now?

A: Run the maintenance script which is idempotent and safe:

```bash
sudo bash /home/adam/worxpace/odus_auto/run_odus_maintenance.sh
```

It runs `dpkg --configure -a`, `apt --fix-broken install -y` and then resumes upgrades. If a kernel package attempted to remove a running kernel, reboot into the intended kernel before attempting removal or use `apt mark hold` on the running kernel to prevent accidental removal.

Q: I want to disable auto updates temporarily

A: Mask the timer or the service:

```bash
sudo systemctl mask odus-autoupdate.timer
sudo systemctl stop odus-autoupdate.timer
```

Q: How can I see what ODUS changed last?

A: Check `/home/adam/worxpace/system_changelog.md` and `/var/log/odus/*` and the system journal: `journalctl -u odus-autoupdate -n 200`.

---

## Security & best practices

- ODUS runs scripts as root (via systemd) so review `/opt/odus/scripts` before enabling in untrusted environments.
- Auto-update attempts to update both system packages and tool signatures (e.g., Nuclei templates) — configure carefully in production.
- Keep `/home/adam/worxpace` workspace private and lock down SSH keys and sudoers for the ODUS admin user.

---

## Files & artifacts (where to find everything)

- Installer: `/home/adam/worxpace/odus_auto/odus.sh`
- Scripts: `/opt/odus/scripts/` (see list above)
- Tools: `/opt/odus/tools` (FlameGraph etc.)
- Systemd units: `/etc/systemd/system/odus-*.service` & `.timer`
- Logs: `/var/log/odus/`
- Benchmarks: any directory you pass to the runner (recommended: `/home/adam/worxpace/benchmarks`)
- Package & inventory artifacts: `/home/adam/worxpace/artifacts/`
- Exhaustive per-package inventory (generated): `/home/adam/worxpace/software_inventory.md`

---

## Changelog & contributions

The local changelog lives at `/home/adam/worxpace/system_changelog.md`. Contributions or improvements can be added by editing scripts under `./scripts` and adding tests to the test harness under `./tests` (not present by default). To install the packaged ODUS from this repo, copy the folder to `/opt/odus` or run the installation routine included in `odus.sh`.

---

If you want, I can: verify all ODUS timers/services are active and healthy, expand the `system.md` software section to include an exhaustive per-package explanation, and add a `docs/` folder with generated package-list artifacts and a searchable index.
