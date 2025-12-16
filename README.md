
# SUPER SCRIPTS 🪖🔧

An opinionated collection of operational and security-focused scripts for developers and operators. Each tool is documented, tested, and intended to be easily discoverable and usable by operators.

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## What you'll find here

- Centralize handy utilities used across multiple projects
- Provide audited, well-documented scripts you can trust
- Make security tools (like HADES) discoverable and easy to run

--

## Included tools

- **hades_env_guard/** — HADES Environment Guard: interactive secret scanner (PowerShell)

- **c.ops_provisioner/** — Cloud Ops provisioning helpers (Python)
- **sys_maintainer/** — System maintenance shell scripts (bash)
- **odus/** — ODUS integration wrapper and documentation (bash)
- **visual_specs/** — Visual system snapshot utility (Python: `matplotlib`, `psutil`)

Each subfolder includes a detailed `README.md` with usage, requirements, and examples.

---

## Quick Start

Clone the repo and run a tool:

```bash
git clone https://github.com/amuzetnoM/super_scripts.git
cd super_scripts
# Examples
bash sys_maintainer/system_maintenance.sh --dry-run
python3 visual_specs/visual_specs.py --outdir /tmp
```

---

## Contribution & Standards

We aim for consistent READMEs with: a short overview, quick start, requirements, examples, and contributing notes. If you add a script, please include a `README.md` following this format and add an entry to this file.

---

## License

MIT

---

If you want, I can open a PR template and add GitHub Actions for linting and basic tests across the Python scripts.
