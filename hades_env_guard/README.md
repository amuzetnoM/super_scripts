# HADES Environment Guard

```
    ░  ░░░░  ░░░      ░░░       ░░░        ░░░      ░░
    ▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒  ▒▒  ▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒
    ▓        ▓▓  ▓▓▓▓  ▓▓  ▓▓▓▓  ▓▓      ▓▓▓▓▓      ▓▓
    █  ████  ██        ██  ████  ██  ██████████████  █
    █  ████  ██  ████  ██       ███        ███      ██

       e n v i r o n m e n t   p r o t e c t i o n
```

> **The gatekeeper of your secrets.** A powerful, interactive PowerShell tool that hunts down hardcoded credentials in any codebase and helps you secure them properly.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/en-us/powershell/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)](https://github.com/PowerShell/PowerShell)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

---

## ⚡ Quick Start

```powershell
# Just run it - that's all you need
.\hades_env_guard.ps1
```

The script will interactively guide you through everything:
1. **Ask for your repository path**
2. **Scan for secrets**
3. **Show you what it found**
4. **Help you sanitize and secure them**

---

## 🔥 What It Does

HADES scans your entire codebase for **hardcoded secrets, API keys, passwords, and credentials** that should never be in version control. It then helps you:

| Feature | Description |
|---------|-------------|
| 🔍 **Smart Detection** | 11 regex patterns catch passwords, API keys, tokens, AWS keys, and more |
| 📊 **Visual Reporting** | Color-coded, organized output grouped by file |
| 🎭 **Masked Preview** | See detected secrets safely: `Sir***888` |
| 🧹 **Auto-Sanitization** | Replace secrets with placeholders in your code |
| 📁 **Env File Export** | Generate `.env.secrets` files automatically |
| ☁️ **GitHub Integration** | Push secrets directly to GitHub repository secrets |
| ➕ **Custom Secrets** | Add additional secrets manually during the session |
| 🏃 **Dry Run Mode** | Preview changes without modifying anything |

---

## 🔎 What It Detects

HADES hunts for these secret patterns:

| Pattern | Example Match |
|---------|---------------|
| **Passwords** | `password=MySecret123` |
| **API Keys** | `api_key=sk_live_abcd1234...` |
| **Secret Keys** | `client_secret=...` |
| **Access Tokens** | `auth_token=eyJhbGci...` |
| **Private Keys** | `-----BEGIN PRIVATE KEY-----` |
| **AWS Credentials** | `aws_secret_access_key=...` |
| **Telegram Tokens** | `telegram_bot_token=123456:ABC...` |
| **GitHub Tokens** | `github_token=ghp_xxxx...` |
| **Login/Account IDs** | `account_id=301073553` |
| **Server Configs** | `server=XMGlobal-MT5 6` |
| **Generic Secrets** | `secret="anything_suspicious"` |

---

## 🚀 Usage

### Basic Usage (Interactive)
```powershell
.\hades_env_guard.ps1
```
You'll be prompted for the repository path and guided through all options.

### Dry Run Mode
```powershell
.\hades_env_guard.ps1 -DryRun
```
Preview what would be detected and changed without modifying any files.

---

## 📸 Example Session

```
  Enter the path to the repository you want to scan:

  Path: C:\workspace\my-project

  +-----------------------------------------------------------------+
  |  SCANNING CODEBASE                                              |
  +-----------------------------------------------------------------+

  [ii] Target: C:\workspace\my-project
  [>>] Found 847 files to analyze...

  [##################################################] 100% (847/847)

  [OK] Scanned 156 sensitive files out of 847 total

  +-----------------------------------------------------------------+
  |  SECRETS DETECTED                                               |
  +-----------------------------------------------------------------+

  [!!] Found 5 potential secrets/credentials:

  FILE: config.json
     +-- [1] Password Field (Line 12): MyS***ord
     +-- [2] API Key (Line 15): sk_***xyz

  FILE: .env.example
     +-- [3] Login/Account ID (Line 3): 301***553
```

---

## 🛡️ Sanitization Options

When secrets are found, HADES offers:

1. **Sanitize ALL** - Replace all secrets with placeholders
2. **Select individually** - Choose which secrets to sanitize
3. **Skip sanitization** - Keep secrets as-is (not recommended)

### What Gets Replaced

| Before | After |
|--------|-------|
| `password=SuperSecret123` | `password=YOUR_PASSWORD_HERE` |
| `api_key=sk_live_abc123` | `api_key=YOUR_API_KEY_HERE` |
| `account_id=301073553` | `account_id=YOUR_ACCOUNT_ID_HERE` |

---

## ☁️ GitHub Secrets Integration

HADES can push your secrets directly to GitHub repository secrets:

```
  +-----------------------------------------------------------------+
  |  GITHUB SECRETS STORAGE                                         |
  +-----------------------------------------------------------------+

  [!!] GitHub CLI not authenticated.

  Would you like to authenticate now? (y/N): y

  [>>] Starting GitHub authentication...
```

### Requirements
- [GitHub CLI](https://cli.github.com/) installed
- If not authenticated, HADES will prompt you to authenticate interactively

---

## 📁 Output Files

### `.env.secrets`
Generated in your target repository with all extracted secrets:
```env
# Generated by HADES Environment Guard
# 2025-12-15 14:30:00

MT5_PASSWORD=SuperSecret123
API_KEY=sk_live_abc123xyz
ACCOUNT_ID=301073553
```

> ⚠️ **Important:** Add `.env.secrets` to your `.gitignore`!

---

## 🚫 Smart Exclusions

HADES automatically skips:

**Directories:**
- `.git`, `node_modules`, `__pycache__`, `venv`, `.venv`
- `dist`, `build`, `.next`, `coverage`, `target`

**Files:**
- Binaries: `*.exe`, `*.dll`, `*.so`, `*.pyc`
- Media: `*.jpg`, `*.png`, `*.mp4`, `*.pdf`
- Lock files: `package-lock.json`, `yarn.lock`

**Placeholders:**
- Lines containing `YOUR_`, `placeholder`, `example`, `TODO`, `CHANGEME`

---

## ⚙️ Requirements

| Requirement | Details |
|-------------|---------|
| **PowerShell** | 5.1+ (Windows) or 7+ (Cross-platform) |
| **GitHub CLI** | Optional - only for GitHub secrets storage |

---

## 🎨 Features

### Beautiful Terminal Output
- Color-coded messages for easy scanning
- Progress bars for long operations
- Organized, boxed sections
- Masked secret values for safe display

### Interactive Workflow
- No complex command-line arguments
- Guided prompts at every step
- Confirmation before any changes
- Add custom secrets on-the-fly

### Safe by Default
- Dry run mode available
- Secrets are always masked in output
- No automatic file modification without consent
- Creates backups in `.env.secrets`

---

## 🔧 Extending HADES

### Adding Custom Patterns

Edit the `$script:SecretPatterns` array in the script:

```powershell
$script:SecretPatterns = @(
    @{ Name = "My Custom Pattern"; Pattern = [regex]::new('(?i)my_secret_key\s*=\s*(\w+)') },
    # ... existing patterns
)
```

### Adding Excluded Directories

```powershell
$script:ExcludedDirs = @(
    '.git', 'node_modules', 'my_custom_dir',
    # ... existing dirs
)
```

---

## 📜 License

MIT License - Use freely, protect your secrets.

---

## 🙏 Philosophy

> *"In Greek mythology, Hades was the guardian of the underworld - keeper of what should remain hidden. This tool serves the same purpose for your codebase: guarding secrets that should never see the light of a public repository."*

---

<div align="center">

**Stop committing secrets. Let HADES protect them.**

```
    █  ████  ██  ████  ██       ███        ███      ██
```

</div>
