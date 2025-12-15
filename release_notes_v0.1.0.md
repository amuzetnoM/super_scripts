# super_scripts v0.1.0 — Initial Release

Release date: 2025-12-15

## Executive Summary

`super_scripts` v0.1.0 is the inaugural release of a compact, audited toolkit for operations and application security. It bundles three primary deliverables:

- **HADES Environment Guard** — an interactive PowerShell secret scanner and manager for safely discovering and sanitizing hard-coded credentials.
- **c.ops_provisioner** — lightweight Python helpers and templates to provision cloud VMs and run basic infra tasks.
- **sys_maintainer** — pragmatic shell utilities for system maintenance and health checks.

This release is designed for engineers and teams that need small, trustworthy utilities to automate routine operations and secure workflows.

---

## Highlights

- Full interactive secret scanning and sanitization workflow (HADES)
- `.env.secrets` export and optional GitHub Secrets storage
- Clear guidance and tooling to scrub secrets from git history (`git-filter-repo`) when needed
- Reusable provisioning templates and test coverage for `c.ops_provisioner`
- Simple, readable shell helpers for common maintenance tasks

---

## HADES — Environment Guard (PowerShell)

HADES is the crown jewel of this release. Key features:

- Interactive repository path prompt and DryRun preview mode
- 11 curated regex-based detection patterns (passwords, API keys, tokens, AWS credentials, private keys, GitHub tokens, Telegram tokens, account IDs, etc.)
- Masked previewing of detected secrets and grouped reports per file
- Three sanitization flows: bulk auto-sanitize, per-item interactive sanitize, or export-only
- Exports secrets to a `.env.secrets` file and can optionally push values to GitHub repository secrets via the `gh` CLI
- Built-in UX helpers: progress bar, boxed sections, colored output, and masked values for safety
- Guidance and helper steps to remove secrets from git history using `git-filter-repo` (examples included)

Usage examples:

```powershell
# Interactive
pwsh ./hades_env_guard.ps1
# Dry run to preview detections
pwsh ./hades_env_guard.ps1 -DryRun
```

Security notes:

- HADES is conservative by default: it will never change files without confirmation (unless you explicitly choose auto-sanitize)
- Always add generated `.env.secrets` to `.gitignore`

---

## c.ops_provisioner (Python)

A small set of helpers to bootstrap cloud resources and VM images for testing or lightweight infra tasks.

Features:

- Example provisioning scripts and an example VM CSV template
- Minimal test coverage and dependency manifest in `requirements.txt`
- Opinionated, documented examples for common cloud tasks

Quick start:

```bash
cd c.ops_provisioner
pip install -r requirements.txt
python cloud_ops_provisioning.py --help
```

---

## sys_maintainer (Shell)

Simple shell scripts focused on system housekeeping:

- `system_maintenance.sh` — routine checks, cleanup steps, and logs rotation
- Clear defaults; safe, idempotent behavior designed for cron job use

Usage:

```bash
bash sys_maintainer/system_maintenance.sh
```

---

## Files of Interest in this Release

- `hades_env_guard/` — HADES PowerShell script + README
- `c.ops_provisioner/` — provisioning helpers, tests and example files
- `sys_maintainer/` — maintenance scripts and documentation
- `README.md` — repo-level documentation
- `release_notes_v0.1.0.md` — this file

---

## Known Limitations & Future Work

- Detection rules are tuned for common patterns; false positives may occur (e.g., `os.getenv`) — interactive review is recommended
- Consider adding scanning for config templates and secrets in binary files in future updates
- Plan: Add CI checks that run `hades_env_guard` in `DryRun` mode on PRs and a release pipeline to auto-generate changelogs

---

## Upgrade & Migration Notes

If you have previously committed secrets and have sanitized your working tree using HADES, follow these steps to scrub history:

```bash
pip install git-filter-repo
# create expressions.txt with patterns to replace
git-filter-repo --replace-text expressions.txt --force
# re-add your remote and force-push
git remote add origin <repo>
git push --force origin main
```

---

## Contributors & Contact

Maintained by `amuzetnoM`. Please open issues for bugs, feature requests, or security reports.

---

## Acknowledgements

Thanks to contributors and testers who helped shape the UX and detection rules.

---

If you want, I can also update the GitHub release body to match these expanded notes and push the change.
