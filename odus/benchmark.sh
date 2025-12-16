#!/usr/bin/env bash
# ODUS Benchmark tool
# Usage: sudo bash odus_benchmark.sh /path/to/benchdir
set -euo pipefail

BENCHDIR=${1:-/home/adam/worxpace/benchmarks}
mkdir -p "$BENCHDIR"
LOG="$BENCHDIR/odus_benchmark.log"
exec > >(tee -a "$LOG") 2>&1

echo "ODUS Benchmark - $(date)"

# Helpers
safe_install() {
  for p in "$@"; do
    if apt-cache policy "$p" | grep -q "Candidate: (none)"; then
      echo "Package $p has no candidate, skipping"
      continue
    fi
    apt-get install -y "$p" || echo "install failed: $p"
  done
}

# Install or skip
echo "Installing benchmark tools (best-effort)"
safe_install sysbench fio || true
# kernel perf
safe_install linux-tools-$(uname -r) linux-tools-common perf || true

# Report structure
REPORT_JSON="$BENCHDIR/odus_benchmark_report.json"
REPORT_MD="$BENCHDIR/odus_benchmark_report.md"

# Run CPU benchmark
cpu_bench() {
  if command -v sysbench >/dev/null 2>&1; then
    NCPU=$(nproc)
    echo "Running sysbench CPU (30s)"; sysbench cpu --threads="$NCPU" --time=30 run > "$BENCHDIR/sysbench_cpu.txt" 2>&1 || true
    CPU_RESULTS=$(tail -n 5 "$BENCHDIR/sysbench_cpu.txt" | sed 's/["/]/\"/g')
  else
    echo "sysbench missing" > "$BENCHDIR/sysbench_skip.txt"; CPU_RESULTS=null
  fi
}

# Memory
mem_bench() {
  if command -v sysbench >/dev/null 2>&1; then
    NCPU=$(nproc)
    sysbench memory --threads="$NCPU" --time=30 --memory-total-size=2G run > "$BENCHDIR/sysbench_mem.txt" 2>&1 || true
    MEM_RESULTS=$(tail -n 5 "$BENCHDIR/sysbench_mem.txt" | sed 's/["/]/\"/g')
  else
    MEM_RESULTS=null
  fi
}

# Disk
disk_bench() {
  if command -v fio >/dev/null 2>&1; then
    fio --name=randread --rw=randread --bs=4k --numjobs=4 --size=1G --runtime=30 --time_based --group_reporting > "$BENCHDIR/fio_randread.txt" 2>&1 || true
    fio --name=randwrite --rw=randwrite --bs=4k --numjobs=4 --size=1G --runtime=30 --time_based --group_reporting > "$BENCHDIR/fio_randwrite.txt" 2>&1 || true
    DISK_RR=$(grep -E "READ:|IOPS|bw=" -n "$BENCHDIR/fio_randread.txt" | tail -n 5 | sed 's/["/]/\"/g' || true)
    DISK_RW=$(grep -E "WRITE:|IOPS|bw=" -n "$BENCHDIR/fio_randwrite.txt" | tail -n 5 | sed 's/["/]/\"/g' || true)
  else
    DISK_RR=null; DISK_RW=null
  fi
}

# Perf stat
perf_bench() {
  if command -v perf >/dev/null 2>&1; then
    perf stat -e cycles,instructions,cache-misses,context-switches,cpu-migrations -a -- sleep 30 > "$BENCHDIR/perf_stat.txt" 2>&1 || true
    PERF_SUMMARY=$(tail -n 20 "$BENCHDIR/perf_stat.txt" | sed 's/["/]/\"/g' || true)
  else
    PERF_SUMMARY=null
  fi
}

cpu_bench
mem_bench
disk_bench
perf_bench

# Produce machine-readable JSON report (pointers + availability)
cat > "$REPORT_JSON" <<JSON
{
  "timestamp": "$(date -u -Iseconds)",
  "cpu_report": "$(if [ -f "$BENCHDIR/sysbench_cpu.txt" ]; then echo "$BENCHDIR/sysbench_cpu.txt"; else echo null; fi)",
  "memory_report": "$(if [ -f "$BENCHDIR/sysbench_mem.txt" ]; then echo "$BENCHDIR/sysbench_mem.txt"; else echo null; fi)",
  "disk_randread": "$(if [ -f "$BENCHDIR/fio_randread.txt" ]; then echo "$BENCHDIR/fio_randread.txt"; else echo null; fi)",
  "disk_randwrite": "$(if [ -f "$BENCHDIR/fio_randwrite.txt" ]; then echo "$BENCHDIR/fio_randwrite.txt"; else echo null; fi)",
  "perf_stat": "$(if [ -f "$BENCHDIR/perf_stat.txt" ]; then echo "$BENCHDIR/perf_stat.txt"; else echo null; fi)",
  "summary_md": "$(if [ -f "$REPORT_MD" ]; then echo "$REPORT_MD"; else echo null; fi)"
}
JSON

# Also produce a short Markdown summary
cat > "$REPORT_MD" <<MD
# ODUS Benchmark Report

**Timestamp:** $(date -u -R)

## CPU (sysbench)

$(if [ -f "$BENCHDIR/sysbench_cpu.txt" ]; then tail -n 20 "$BENCHDIR/sysbench_cpu.txt"; else echo "sysbench CPU: skipped"; fi)

## Memory (sysbench)

$(if [ -f "$BENCHDIR/sysbench_mem.txt" ]; then tail -n 20 "$BENCHDIR/sysbench_mem.txt"; else echo "sysbench memory: skipped"; fi)

## Disk (fio)

### randread

$(if [ -f "$BENCHDIR/fio_randread.txt" ]; then tail -n 20 "$BENCHDIR/fio_randread.txt"; else echo "fio randread: skipped"; fi)

### randwrite

$(if [ -f "$BENCHDIR/fio_randwrite.txt" ]; then tail -n 20 "$BENCHDIR/fio_randwrite.txt"; else echo "fio randwrite: skipped"; fi)

## Perf Stat

$(if [ -f "$BENCHDIR/perf_stat.txt" ]; then tail -n 20 "$BENCHDIR/perf_stat.txt"; else echo "perf stat: skipped"; fi)

MD

echo "Benchmark finished. JSON report: $REPORT_JSON, summary: $REPORT_MD"
