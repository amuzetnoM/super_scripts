# sys_maintainer

Lightweight system maintenance helper script for Debian/Ubuntu hosts. It performs package updates, basic container health checks, and records system metrics to a log file. The script is intentionally simple so it can be scheduled via cron or run ad-hoc.

## Files
- `system_maintenance.sh` — main script.

## Features
- Safe execution: `set -euo pipefail`, `trap` on exit.
- Dry-run mode to preview actions without making changes.
- Detects `apt-get` and `docker` presence before running related commands.
- Rotates the log file when larger than 5MB.

## Usage

Make executable and run:

```bash
chmod +x system_maintenance.sh
./system_maintenance.sh --log-file /var/log/gemini_maintenance.log --container my_app
```

Dry run:

```bash
./system_maintenance.sh --dry-run
```

## Scheduling (example cron)

Run daily at 3am:

```cron
0 3 * * * /path/to/system_maintenance.sh --log-file /var/log/gemini_maintenance.log
```

## Notes
- The script uses `apt-get`; on non-Debian systems it will skip package updates.
- It uses `sudo` automatically when not run as root.
