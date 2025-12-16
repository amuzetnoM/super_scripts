# Visual Specs

`visual_specs` is a small utility that collects compact system metrics and renders them into a single image (PNG) and a compact JSON summary.

Key points:
- Single PNG with a quick visual summary (platform, CPU, memory, disk, per-core utilisation, top processes)
- Compact JSON for automation and archival
- Intended to be easily run on CI or ad-hoc on a host

## Quick Start

```bash
python visual_specs.py --outdir /tmp
ls /tmp/visual_specs.*
```

## Requirements
- Python 3.8+
- `matplotlib`, `psutil`

## Output
- `visual_specs.png` — visual summarised snapshot
- `visual_specs.json` — compact numeric summary

## Use Cases
- Periodically capture a host snapshot for trend analysis
- Collect targeted metrics during debugging and attach the single PNG to an incident report
- Integrate into automation: run via cron or systemd timer and upload compressed snapshots to an artifact store

## License
MIT
