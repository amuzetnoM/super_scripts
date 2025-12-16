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
