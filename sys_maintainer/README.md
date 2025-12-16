# sys_maintainer

[![License](https://img.shields.io/badge/license-MIT-green.svg)](../LICENSE)

A lightweight system maintenance helper for Debian/Ubuntu hosts. Designed to be scheduled via cron or run ad-hoc.

## Features
- Safe execution (`set -euo pipefail`) and fail-safe traps
- Dry-run mode
- Detects `apt-get` and `docker` before running commands
- Log rotation when logs exceed a size threshold

## Quick Start

```bash
chmod +x system_maintenance.sh
./system_maintenance.sh --dry-run
```

## Scheduling
Example cron job (daily at 03:00):

```cron
0 3 * * * /path/to/system_maintenance.sh --log-file /var/log/maintenance.log
```

## Notes
- Non-Debian systems will skip package-update steps gracefully.
- The script uses `sudo` when required.

## Contributing
Open issues or PRs. Provide repro steps and platform details.

## License
MIT
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
