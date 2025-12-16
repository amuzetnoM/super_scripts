#!/usr/bin/env bash
set -euo pipefail

ODUS_DIR="/opt/odus/scripts"
LOG_FILE="/var/log/odus/odus_wrapper.log"

usage(){
  cat <<EOF
Usage: $0 <command>
Commands:
  status          show presence and versions
  intelligence    run odus-intelligence (if present)
  cleanup [mode]  run odus-cleanup.sh with optional mode (standard|deep|emergency)
  benchmark run   run odus benchmarks (if installed)
EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 1
fi

cmd="$1"
shift || true

if [ ! -d "$ODUS_DIR" ]; then
  echo "ODUS scripts not found at $ODUS_DIR. Install ODUS or adjust the wrapper." >&2
  exit 2
fi

case "$cmd" in
  status)
    echo "ODUS present at $ODUS_DIR"
    ls -1 "$ODUS_DIR" || true
    ;;
  intelligence)
    if [ -x "$ODUS_DIR/odus-intelligence.py" ]; then
      "$ODUS_DIR/odus-intelligence.py" "$@"
    else
      echo "odus-intelligence.py not found or not executable" >&2
      exit 3
    fi
    ;;
  cleanup)
    mode="standard"
    if [ $# -ge 1 ]; then mode="$1"; fi
    if [ -x "$ODUS_DIR/odus-cleanup.sh" ]; then
      sudo "$ODUS_DIR/odus-cleanup.sh" "$mode"
    else
      echo "odus-cleanup.sh not found or not executable" >&2
      exit 4
    fi
    ;;
  benchmark)
    if [ "$1" = "run" ]; then
      if [ -x "$ODUS_DIR/odus_benchmark.sh" ]; then
        sudo "$ODUS_DIR/odus_benchmark.sh" "$@"
      else
        echo "odus_benchmark.sh not found" >&2
        exit 5
      fi
    else
      usage
      exit 1
    fi
    ;;
  *)
    usage
    exit 1
    ;;
esac
