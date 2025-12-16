#!/usr/bin/env bash
set -euo pipefail

LOG=/home/adam/worxpace/odus_auto/maintenance_run.log
BENCHDIR=/home/adam/worxpace/benchmarks
CHANGELOG=/home/adam/worxpace/system_changelog.md
PKGLIST=/home/adam/worxpace/installed_packages_after.txt

mkdir -p "$(dirname "$LOG")" "$BENCHDIR"
exec > >(tee -a "$LOG") 2>&1

echo "===== ODUS Maintenance Run - $(date) ====="

echo "-- Fixing package state --"
export DEBIAN_FRONTEND=noninteractive
sudo dpkg --configure -a || true
sudo apt --fix-broken install -y || true
sudo apt update -qq || true
sudo apt upgrade -y -qq || true

echo "-- Capturing package list --"
dpkg -l > "$PKGLIST" || true

# Optional: run external benchmarking tool if present
if [ -x /home/adam/worxpace/odus_auto/odus_benchmark.sh ]; then
  echo "Found odus_benchmark.sh - running benchmarks (best-effort)"
  sudo bash /home/adam/worxpace/odus_auto/odus_benchmark.sh "$BENCHDIR" || true
else
  echo "No benchmark tool found at /home/adam/worxpace/odus_auto/odus_benchmark.sh - skipping benchmarks"
  echo "benchmarks skipped" > "$BENCHDIR/benchmarks_skipped.txt"
fi

# Restart ODUS systemd services and check statuses
echo "-- Restarting ODUS services and collecting unit status --"
SERVICES=(odus-autoupdate odus-cleanup-weekly odus-cleanup-biweekly odus-intelligence odus-selfheal odus-backup)
for s in "${SERVICES[@]}"; do
  if systemctl list-unit-files | grep -q "^${s}\.service"; then
    sudo systemctl restart "$s" || true
    sudo systemctl status --no-pager "$s" > "$BENCHDIR/status_$s.txt" || true
  fi
done

# Clean apt residues
echo "-- Cleaning up packages --"
sudo apt autoremove -y -qq || true
sudo apt autoclean -y -qq || true

# Archive benchmarks & logs
ARCHIVE=/home/adam/worxpace/benchmarks_$(date +%Y%m%d_%H%M%S).tar.gz
tar -czf "$ARCHIVE" -C /home/adam/worxpace benchmarks maintenance_run.log installed_packages_after.txt 2>/dev/null || true

# Write changelog
cat > "$CHANGELOG" <<EOF
# ODUS System Changelog

- Date: $(date -u -R)
- Action: Maintenance run (dpkg fix, apt --fix-broken, upgrades, benchmark collection)
- Benchmarks: saved to $BENCHDIR and archive $ARCHIVE
- Packages snapshot: $PKGLIST
- Notes: Please review $LOG for full output.

EOF

# If benchmark summary exists, append short findings
if [ -f "$BENCHDIR/odus_benchmark_report.md" ]; then
  echo "\n## Benchmark summary ($(date -u -R))" >> "$CHANGELOG"
  echo "" >> "$CHANGELOG"
  # include first ~40 lines of the benchmark report
  sed -n '1,40p' "$BENCHDIR/odus_benchmark_report.md" >> "$CHANGELOG"
  echo "" >> "$CHANGELOG"
else
  echo "No benchmark report present to summarize" >> "$CHANGELOG"
fi

echo "Maintenance run completed. Benchmarks and logs saved to $BENCHDIR and $ARCHIVE"

# Print short summary
echo "-- Brief benchmark summary --"
[ -f "$BENCHDIR/sysbench_cpu.txt" ] && tail -n 10 "$BENCHDIR/sysbench_cpu.txt" || true
[ -f "$BENCHDIR/fio_randread.txt" ] && tail -n 5 "$BENCHDIR/fio_randread.txt" || true
[ -f "$BENCHDIR/perf_stat.txt" ] && tail -n 5 "$BENCHDIR/perf_stat.txt" || true

echo "Maintenance script finished. If you want, send me the artifacts or I can analyze them here once they exist."
