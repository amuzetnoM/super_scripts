#!/usr/bin/env bash
# ssh_verify.sh
# Run on the VM to verify SSH, VNC service, firewall, and authorized keys.
# Usage: sudo bash ssh_verify.sh

set -euo pipefail

echo "=== Verification: SSH, VNC, Firewall, Keys ==="

echo "-- sshd status --"
systemctl status sshd --no-pager || systemctl status ssh --no-pager || true

echo "-- sshd config (Pubkey/Password) --"
grep -E '^\s*PubkeyAuthentication|^\s*PasswordAuthentication|^\s*PermitRootLogin' /etc/ssh/sshd_config || true

echo "-- authorized_keys (for default user ali_shakil_backup) --"
ls -l /home/ali_shakil_backup/.ssh || true
cat /home/ali_shakil_backup/.ssh/authorized_keys || true

echo "-- VNC service status --"
systemctl status vncserver@1.service --no-pager || true

echo "-- Listening ports (22 and 5901) --"
ss -ltnp | grep -E ':22|:5901' || true

echo "-- Firewall rules (UFW or firewalld) --"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --list-all || true
else
  echo "No ufw/firewalld detected; check iptables rules manually:" && iptables -L -n --line-numbers || true
fi

echo "=== End verification ==="
exit 0
