# ODUS Integration

A small wrapper to integrate the system-wide **ODUS** automation scripts into this repository for discoverability and convenience.

This folder contains a thin shell wrapper (`odus.sh`) that executes the ODUS tooling installed under `/opt/odus/scripts` when present. It also documents how to install ODUS, run intelligence, cleanup, and benchmark tasks.

## Why include ODUS here?
- Make ODUS discoverable from the `super_scripts` collection
- Provide a consistent README and usage reference
- Offer a small wrapper to run common ODUS subcommands from repos that lack a global install

## Requirements
- ODUS installed under `/opt/odus` (scripts live in `/opt/odus/scripts`)
- `bash` and typical POSIX utilities

## Usage
Make the wrapper executable and run a subcommand:

```bash
chmod +x odus.sh
./odus.sh status
./odus.sh intelligence
./odus.sh cleanup standard
./odus.sh benchmark run
```

The wrapper will check for `/opt/odus/scripts` and fail with a helpful message if ODUS is not installed.

## Installing ODUS
If ODUS is not present, follow the project's install instructions (see system administrator docs). The wrapper expects scripts at `/opt/odus/scripts/` like `odus-intelligence.py` and `odus-cleanup.sh`.

## License
MIT
