# Cloud Ops Provisioner

[![Python](https://img.shields.io/badge/python-3.8%2B-blue)](https://www.python.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](../LICENSE)

A small, single-file CLI tool (`cloud_ops_provisioning.py`) to provision Google Cloud Ops agents across many VM instances. It supports multiple execution providers (`local-gcloud`, `paramiko`, `mock`), concurrency, retries, and state management.

## Features
- Concurrent provisioning using `ThreadPoolExecutor`
- Pluggable providers: `local-gcloud`, `paramiko`, `mock` (dry-run)
- State file to avoid re-provisioning
- Retries with exponential backoff and logging
- Test suite included under `test/`

## Quick Start

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt  # if using paramiko
python cloud_ops_provisioning.py --file example_vms.csv --max-workers 10
```

## Requirements
- Python 3.8+
- `gcloud` (if using `local-gcloud` provider)
- `paramiko` (optional provider)
- **Concurrent Execution:** Uses `ThreadPoolExecutor` to provision multiple instances in parallel.
- **Provider Abstraction:** Built-in providers include `local-gcloud` (uses `gcloud compute ssh`), `paramiko` (direct SSH using `paramiko`), and a `mock` dry-run provider for testing.
- **State Management:** Records provisioning status in a state file to avoid re-running successful installs unless forced.
- **Automatic Retries:** Retries failed commands with exponential backoff.
- **Configurable CLI:** Exposes `--provider`, `--dry-run`, `--ssh-user`, `--ssh-key`, and other familiar flags.
- **Robust Validation & Logging:** Validates input and writes per-run and per-instance logs.
- **Test Suite Included:** Unit tests for validation and core logic are included under `test/`.

## 3. Prerequisites

- Python 3.8+
- If using `local-gcloud`: Google Cloud SDK (`gcloud`) installed and authenticated.
- If using `paramiko` provider: install `paramiko` (`pip install -r requirements.txt`).

## 4. Installation

1. Copy the single script `cloud_ops_provisioning.py` into a folder (this repo already includes it).
2. (Optional) Create a virtual environment and install requirements:

```bash
python -m venv .venv
source .venv/bin/activate  # or .\.venv\Scripts\activate on Windows
pip install -r requirements.txt
```

## 5. Usage

Run the script with the required `--file` argument.

```bash
python cloud_ops_provisioning.py --file example_vms.csv [OPTIONS]
```

### Command-Line Arguments

- `--file` (required): Path to the input CSV containing instance names and agent rules.
- `--max-workers` (default: 10): Maximum concurrent workers.
- `--force`: Force re-provisioning of all VMs (ignore state file).
- `--max-retries` (default: 3): Maximum number of retries for failed commands.
- `--provider` (default: `local-gcloud`): Execution provider to use. Built-ins: `local-gcloud`, `paramiko`, `mock`.
- `--dry-run`: Shortcut to use the `mock` provider and simulate installs.
- `--ssh-user`: SSH username for `paramiko` provider.
- `--ssh-key`: Path to private SSH key for `paramiko` provider.

Example (local gcloud):

```bash
python cloud_ops_provisioning.py --file example_vms.csv --max-workers 20
```

Example (paramiko provider):

```bash
python cloud_ops_provisioning.py --file example_vms.csv --provider paramiko --ssh-user ubuntu --ssh-key ~/.ssh/id_rsa
```

Dry run:

```bash
python cloud_ops_provisioning.py --file example_vms.csv --dry-run
```

## 6. Input File Format

Same as before: CSV with two columns:

- Column 1: Full instance name `projects/PROJECT_ID/zones/ZONE/instances/INSTANCE_NAME`.
- Column 2: JSON string of agent rules (array of objects with `type` and optional `version`).

### Agent Rules

- `type`: `"logging"`, `"metrics"`, or `"ops-agent"`.
- `version`: `"latest"`, `MAJOR.MINOR.PATCH` (e.g. `"1.2.3"`), or `MAJOR.*.*`.

Example `example_vms.csv`:

```csv
"projects/my-project/zones/us-central1-a/instances/instance-1","[{\"type\":\"ops-agent\",\"version\":\"1.*.*\"}]"
"projects/my-project/zones/us-central1-a/instances/instance-2","[{\"type\":\"logging\",\"version\":\"1.*.*\"},{\"type\":\"metrics\",\"version\":\"6.*.*\"}]"
"projects/my-project/zones/us-central1-a/instances/instance-3","[{\"type\":\"ops-agent\",\"version\":\"latest\"}]"
```

Note: `ops-agent` cannot be combined with other agent types for the same VM.

## 7. State Management

The script stores `provisioning_state.json` in the `google_cloud_ops_agent_provisioning/` directory. Use `--force` to ignore it.

## 8. Logging

Per-run and per-instance logs are written under `google_cloud_ops_agent_provisioning/`.

## 9. Error Handling and Retries

Automatic retries with exponential backoff are used; failing instances are marked `FAILURE` after exceeding retries.

## 10. Testing

Unit tests are included in `test/test_provisioning.py`. Run them with `pytest`:

```bash
pytest -q
```

## 11. Security

- Do not commit private keys or credentials.
- Use least-privileged accounts on instances and ensure SSH keys are protected.

## 12. Contributing

Contributions welcome. Open issues or PRs with details and steps to reproduce.

## 13. License

This repository does not include a license file by default. Add a suitable license (e.g., MIT) if you plan to publish.
Mass Provisioning - Google Cloud Ops Agents Installer

Overview

This repository contains a small, single-file CLI tool for provisioning Google Cloud Ops agents (logging, metrics, Ops Agent) across many VM instances.

The script reads a CSV-like file containing instance full names and JSON-encoded agent rules per instance, validates the inputs, and then executes installer commands on each VM. It supports pluggable execution backends (providers) and includes built-in providers for:

- local-gcloud: Executes `gcloud compute ssh` locally to run the installer commands remotely.
- paramiko: Uses SSH via `paramiko` for environments without `gcloud`.
- mock (dry-run): Simulates successful installs useful for testing.

Design goals

- Single-file entrypoint: The core logic is contained in `cloud_ops_provisioning.py` so the tool can be used as a single, portable script.
- Provider abstraction: Execution of remote commands is pluggable so the tool can work across environments (local `gcloud`, direct SSH, remote APIs, etc.).
- Testability: The script exposes a `_popen` wrapper that tests mock, and the provider abstraction makes it easy to simulate installs.
- Safety: Avoids `shell=True` usage for `gcloud` invocation and performs careful logging and validation.

Quickstart

1. Requirements

- Python 3.8+
- `gcloud` (if using `local-gcloud` provider)
- Optional: `paramiko` package if you plan to use the `paramiko` provider

Install runtime dependencies (for paramiko provider):

```bash
pip install paramiko
```

2. Usage

Prepare an input CSV file where each row is a pair: `"instance_full_name","agent_rules"`.

- `instance_full_name` must be in the format: `projects/<project>/zones/<zone>/instances/<instance>`
- `agent_rules` is a JSON array of objects, each containing at least a `type` field and optionally `version`. Example:

```csv
"projects/my-project/zones/us-central1-a/instances/instance-1","[{\"type\": \"logging\", \"version\": \"latest\"}]"
```

Run the installer (local gcloud):

```bash
python cloud_ops_provisioning.py --file vms.csv --max-workers 20
```

Dry run (no network calls):

```bash
python cloud_ops_provisioning.py --file vms.csv --dry-run
```

Use the paramiko provider (requires `paramiko` and that the instance hostnames are reachable):

```bash
python cloud_ops_provisioning.py --file vms.csv --provider paramiko --ssh-user ubuntu --ssh-key ~/.ssh/id_rsa
```

CLI flags

- `--file`: Path to input CSV file (required).
- `--max-workers`: Maximum concurrent workers (default 10).
- `--force`: Ignore previous state and re-run installs.
- `--max-retries`: Number of retries for SSH command failures (default 3).
- `--provider`: Execution provider to use (`local-gcloud`, `paramiko`, `mock`).
- `--dry-run`: Use mock provider to simulate operations.
- `--ssh-user`: SSH username for the paramiko provider.
- `--ssh-key`: Path to the private SSH key for the paramiko provider.

Implementation details

Parsing and validation

- The script reads the provided file and uses `csv.reader` to parse lines.
- Each `agent_rules` BLOB is JSON-decoded and must contain at least one rule. Each rule requires `type` and optionally accepts `version`.
- Agent type validation ensures only supported agent types (`logging`, `metrics`, `ops-agent`) are used and enforces that `ops-agent` cannot be combined with other agent types.
- Version pinning is validated against allowed patterns: `latest`, `MAJOR.*.*`, or full `MAJOR.MINOR.PATCH`.

Execution model

- A `Provisioner` manages many `ProvisioningTask` instances and runs them via a `ThreadPoolExecutor`.
- Each `ProvisioningTask` constructs the sequence of remote shell commands to add the repository, install the agent, and check that it runs.
- The provider abstraction handles how the remote command is executed:
  - `local-gcloud` builds a `gcloud compute ssh ... --command "..."` argv and runs it via a safe `subprocess.Popen` (no `shell=True`).
  - `paramiko` connects directly to the given hostname using `paramiko` and runs the command.
  - `mock` returns a simulated process that always succeeds.

State and logs

- The Provisioner writes a JSON state file (`google_cloud_ops_agent_provisioning/provisioning_state.json`) recording last status per instance to avoid re-running installs by default.
- Per-instance logs are written into the `google_cloud_ops_agent_provisioning/` directory.

Security considerations

- The script avoids `shell=True` for `gcloud` invocation to reduce injection risk.
- When using `paramiko`, ensure private key files have correct filesystem permissions and consider using an SSH agent.
- Running the installer requires elevated privileges on the target VMs; ensure the user has proper authorization.

Extensibility

- Provider interface is intentionally small; you can add providers that call cloud provider APIs (e.g., use the Compute Engine API's SSH-like functionality or use a fleet management API) or implement different authentication methods.
- You can swap state backend (file -> GCS/Cloud SQL/Redis) and log storage (local files -> GCS/S3).

Testing

- Unit tests are provided under `test/` and use a shim module so they can import the main API easily.
- The script includes `_popen` wrapper to make mocking subprocess creation straightforward.

Development roadmap / recommendations

- Add an integration test harness that can run against a test project and ephemeral VMs.
- Implement a `provider` plugin mechanism that discovers providers in a `providers/` directory or via entry points.
- Add retries with jitter and a circuit breaker to handle partial failures and API rate limits.
- Add better output formats (JSON summary, machine-readable logs) and integration with observability systems.

Support / Contribution

Open an issue or PR with a clear description and reproduction steps. Include platform details, Python version, and the `--provider` you are using.

License

No license file currently provided — add one if you plan to publish.
