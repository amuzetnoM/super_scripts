# SSH & VNC Dev Guide — VM (developer-only)

> **Developer-only:** this guide documents the current automated setup and how to reproduce and verify it. It contains **dev secrets** (VNC password, server IPs, public keys) and should not be committed to public repositories.

---

## ✅ Current status (what's configured)
- Host scripts and docs placed in: `C:\workspace\_dev\virtual_machine` (see files list below).  
- VNC (TightVNC) installed and running as a systemd service on the VM (display `:1`, port 5901).  
- VNC configured to bind to **localhost only** (so VNC is reachable only via SSH tunnels).  
- OpenSSH server installed and running (sshd), configured for **public-key auth only**.  
- Firewall: SSH (TCP 22) allowed; public VNC port (5901) blocked.  
- Developer secrets (VNC password, server public IP, public keys) are written to `DEV_SECRETS.md` (developer-only file in the same directory).

---

## Files in `C:\workspace\_dev\virtual_machine`
- `host_setup_auto.sh` — idempotent host installer (TightVNC, OpenSSH, firewall, VNC password generation or set). 🔧
- `client_setup_auto.sh` — client helper: generate key (if needed), print public key, try `ssh-copy-id`, install viewer, display tunnel command. 💻
- `ssh_verify.sh` — verification script to confirm SSH, VNC service, firewall, and authorized_keys. 🧪
- `vm_finish_setup.sh` — previous utility to set VNC password and create drop-in (kept for compatibility). ⚙️
- `client_connect.sh` — simple client tunnel + viewer launcher (kept for compatibility). 🔗
- `DEV_SECRETS.md` — developer-only secrets (VNC password, server IP, public keys). 🔐

---

## Quick runbook — host (VM) — one command to ensure system is configured
1. Copy or verify `host_setup_auto.sh` is present on the VM at `C:\workspace\_dev\virtual_machine` (or in `/home` on Linux VM).  
2. Run as root (the script is idempotent and safe to re-run):

```bash
# on the VM (Linux) — example
sudo bash /path/to/host_setup_auto.sh            # generates a VNC password and writes DEV_SECRETS.md
# or provide a password explicitly (if you prefer):
sudo bash /path/to/host_setup_auto.sh MyVncPassword123
```

What the host script does (summary):
- Installs required packages (TightVNC, OpenSSH, expect, UFW/firewalld or applies iptables fallback).  
- Creates the VNC user (if missing) and sets a VNC password (non-interactively via `expect`).  
- Writes a systemd override to run the VNC server with `-localhost` (bind to 127.0.0.1).  
- Enables and starts the vncserver instance (display `:1` → port 5901).  
- Ensures `sshd` is enabled and restarts it with `PubkeyAuthentication yes` and `PasswordAuthentication no` (backup saved).  
- Opens the firewall for SSH and removes public VNC rules (or drops 5901 via iptables).  
- Writes a developer-only `DEV_SECRETS.md` file that contains the **VNC password**, server IP, and public keys.

---

## Quick runbook — client (Linux) — one command to prepare and get the public key
1. On your Linux client run the client script to ensure you have keys and to print the public key:

```bash
bash client_setup_auto.sh ali_shakil_backup 34.155.169.168
```
- This will generate `~/.ssh/id_ed25519` if missing and print `~/.ssh/id_ed25519.pub`.  
- Copy the printed public key and either use `ssh-copy-id` (if enabled) or add it to the VM `/home/ali_shakil_backup/.ssh/authorized_keys` via the cloud console or `scp`/`ssh`.

2. Once your public key is installed on the VM, use the tunnel command (client):

```bash
ssh -i ~/.ssh/id_ed25519 -L 5901:localhost:5901 ali_shakil_backup@34.155.169.168
# or background:
ssh -f -N -i ~/.ssh/id_ed25519 -L 5901:localhost:5901 ali_shakil_backup@34.155.169.168
# then open your VNC viewer and connect to: localhost:5901
```

VNC password (dev): `2eMFeJZwDqWW9Yjk` — stored in `DEV_SECRETS.md` (dev-only).

---

## Verification — run these on the VM
Run the verification script on the VM and paste output here if you want me to review:

```bash
sudo bash /path/to/ssh_verify.sh
```

Manual checks (single commands):
- Check `sshd` status:
```bash
sudo systemctl status sshd --no-pager || sudo systemctl status ssh --no-pager
```
- Check `sshd` config for key-only:
```bash
sudo grep -E '^\s*PubkeyAuthentication|^\s*PasswordAuthentication' /etc/ssh/sshd_config
```
- Confirm `authorized_keys` and permissions:
```bash
ls -ld /home/ali_shakil_backup/.ssh
ls -l /home/ali_shakil_backup/.ssh/authorized_keys
```
- Confirm VNC is listening on localhost only:
```bash
ss -ltnp | grep 5901
# expect: 127.0.0.1:5901 (LISTEN)
```
- Confirm firewall rules (UFW example):
```bash
sudo ufw status verbose
```

---

## Secrets & dev docs (where to find them)
**Dev secrets file:** `C:\workspace\_dev\virtual_machine\DEV_SECRETS.md` (Linux path: `/path/to/DEV_SECRETS.md` if you copied it to Linux).  
The file contains (developer-only):
- VNC password: `2eMFeJZwDqWW9Yjk`  
- Server public IP: `34.155.169.168`  
- Public keys currently present (public keys only):
  - `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJxppVG+... ali.shakil.backup@gmail.com`  
  - `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDXpFBAR9Fv... ali_shakil_backup@odyssey`

> Security: This file is for development only. Do **not** commit it to public repositories and rotate secrets before production.

---

## How to rotate VNC password and remove old keys (safe ops)
- Rotate VNC password (non-interactive): re-run host script with a new password:
```bash
sudo bash /path/to/host_setup_auto.sh NewVncSecret123
```
- Remove a public key from the VM:
```bash
# edit the authorized_keys file and remove the line, then save
sudo sed -i "/AAAAC3NzaC1lZDI1NTE5AAAAIDXpFBAR9FvAO85g3FsA/d" /home/ali_shakil_backup/.ssh/authorized_keys
sudo chmod 600 /home/ali_shakil_backup/.ssh/authorized_keys
```

---

## Rollback (if needed)
- Restore `sshd_config` backup:
```bash
sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
sudo systemctl restart sshd
```
- Revert firewall rules (UFW example):
```bash
sudo ufw delete allow OpenSSH
# then re-add any previous VNC rules if absolutely necessary
```

---

## Final notes & sign-off
- Everything in this guide is reproducible with the provided scripts. Run `ssh_verify.sh` after changes and paste the output here if you want me to reconfirm.  
- If you want me to rotate secrets, remove DEV secrets, or convert to TigerVNC for easier scripting, reply with the action and I’ll prepare the change-set.

---

If you want me to: **(A)** run the host script on the VM now (I have SSH access now), **(B)** run verification now, or **(C)** walk you through the client steps on your machine, reply with A / B / C and I will proceed.
