
#  SUPER SCRIPTS 🪖🔧


An opinionated collection of operational and security-focused scripts for developers and operators — curated tools to help run, secure, and maintain projects.

This repository hosts small, well-tested utilities such as **HADES Environment Guard** (a universal secret scanner and manager), provisioning helpers, and system maintenance scripts.

--

## Why this repo?

- Centralize handy utilities used across multiple projects
- Provide audited, well-documented scripts you can trust
- Make security tools (like HADES) discoverable and easy to run

--

## Included tools

- **hades_env_guard/** — HADES Environment Guard: interactive secret scanner and manager (PowerShell)
- **c.ops_provisioner/** — Cloud Ops provisioning helpers (Python)
- **sys_maintainer/** — System maintenance shell scripts

Each tool contains its own README and usage examples. See the folders for details.

--

## Quick Start

Clone the repo and run the HADES scanner:

```bash
git clone https://github.com/amuzetnoM/super_scripts.git
cd super_scripts/hades_env_guard
pwsh ./hades_env_guard.ps1
```

HADES will prompt you for the repository path to scan and guide you through sanitization and secure storage.

--

## Security & Best Practices

- Always run HADES or equivalent scanners before publishing or sharing repositories.
- Keep secrets out of the repo: use `.env` files protected by `.gitignore`, and store runtime secrets in secret stores (GitHub Secrets, HashiCorp Vault, etc.)
- If a secret is committed, use `git-filter-repo` (installed via pip) to scrub history safely.

--

## Contributing

Contributions are welcome. Please open issues for bugs or feature requests and submit PRs with tests and documentation.

--

## License

MIT

--

If you'd like, I can also add CI checks (linting, unit tests) and an automated release workflow for this repo.
