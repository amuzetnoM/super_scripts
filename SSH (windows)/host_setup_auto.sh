#!/usr/bin/env bash
# host_setup_auto.sh
# Complete, idempotent host setup for TightVNC + OpenSSH on Debian/Ubuntu-like systems.
# Usage: sudo bash host_setup_auto.sh [vnc_password] [vnc_user]
# - If vnc_password is omitted, a strong password will be generated and printed.
# - Default vnc_user: ali_shakil_backup

set -euo pipefail
VNC_PASS=${1:-""}
VNC_USER=${2:-ali_shakil_backup}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECRETS_FILE="$SCRIPT_DIR/DEV_SECRETS.md"

echo "=== Host setup starting (TightVNC + OpenSSH + firewall hardening) ==="
[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }

# Utilities
genpass() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 || (openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c 16); }

# Ensure package manager present
if command -v apt-get >/dev/null 2>&1; then
  PM=apt
elif command -v yum >/dev/null 2>&1; then
  PM=yum
else
  echo "Unsupported distro: please install TightVNC, OpenSSH and expect manually." >&2
  exit 2
fi

# Install packages idempotently
echo "Installing required packages (tightvncserver, openssh-server, expect)..."
if [ "$PM" = apt ]; then
  apt-get update -y
  apt-get install -y tightvncserver openssh-server expect ufw || true
else
  yum install -y tigervnc-server openssh-server expect firewalld || true
fi

# Create VNC user if missing
if ! id -u "$VNC_USER" >/dev/null 2>&1; then
  echo "Creating user $VNC_USER ..."
  useradd -m -s /bin/bash "$VNC_USER"
  passwd -l "$VNC_USER" || true
else
  echo "User $VNC_USER exists"
fi

# Prepare .ssh directory (owner must be VNC_USER)
VNC_HOME=$(getent passwd "$VNC_USER" | cut -d: -f6)
mkdir -p "$VNC_HOME/.ssh"
chown "$VNC_USER:$VNC_USER" "$VNC_HOME/.ssh"
chmod 700 "$VNC_HOME/.ssh"

# Set/generate VNC password
if [ -z "$VNC_PASS" ]; then
  VNC_PASS=$(genpass)
  echo "Generated VNC password: $VNC_PASS"
else
  echo "Using provided VNC password"
fi

echo "Setting VNC password for $VNC_USER (non-interactive)..."
# Use expect to script vncpasswd as the VNC user
runuser -l "$VNC_USER" -c "/usr/bin/expect <<'EXPECT'
spawn vncpasswd
expect \"Password:\"
send \"${VNC_PASS}\r\"
expect \"Verify:\"
send \"${VNC_PASS}\r\"
expect eof
EXPECT"

# Secure VNC files
if [ -d "$VNC_HOME/.vnc" ]; then
  chown -R "$VNC_USER:$VNC_USER" "$VNC_HOME/.vnc"
  chmod 700 "$VNC_HOME/.vnc"
  [ -f "$VNC_HOME/.vnc/passwd" ] && chmod 600 "$VNC_HOME/.vnc/passwd"
fi

# Configure systemd unit (override) to force -localhost binding
echo "Configuring systemd drop-in to force VNC to bind to localhost only..."
mkdir -p /etc/systemd/system/vncserver@.service.d
cat >/etc/systemd/system/vncserver@.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/vncserver -localhost -depth 24 -geometry 1280x800 :%i
EOF
systemctl daemon-reload
systemctl enable --now vncserver@1.service || true
systemctl restart vncserver@1.service || echo "Warning: vncserver restart failed"

# Ensure SSH server enabled and configured for key-only auth
echo "Ensuring OpenSSH server is running and key auth enforced..."
if systemctl list-unit-files | grep -q '^sshd\.service'; then
  systemctl enable --now sshd || true
else
  systemctl enable --now ssh || true
fi

SSHD_CONF=/etc/ssh/sshd_config
if [ -f "$SSHD_CONF" ]; then
  cp -n "$SSHD_CONF" "$SSHD_CONF.bak" || true
  sed -i 's/^#*\s*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONF" || true
  sed -i 's/^#*\s*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONF" || true
  sed -i 's/^#*\s*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' "$SSHD_CONF" || true
  systemctl restart sshd || systemctl restart ssh || true
fi

# Firewall: allow SSH, block public VNC
echo "Configuring firewall: allow SSH, block VNC public access (5901)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow OpenSSH || true
  ufw delete allow 5901/tcp || true
  ufw --force enable || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=ssh || true
  firewall-cmd --permanent --remove-port=5901/tcp || true
  firewall-cmd --reload || true
else
  if ! iptables -C INPUT -p tcp --dport 5901 -j DROP >/dev/null 2>&1; then
    iptables -I INPUT -p tcp --dport 5901 -j DROP || true
  fi
fi

# Verification checks
echo "Verifying services and ports..."
systemctl status vncserver@1.service --no-pager || true
systemctl status sshd --no-pager || systemctl status ssh --no-pager || true
ss -ltnp | grep 5901 || true
ss -ltnp | grep :22 || true

# Write DEV secrets doc (developer-only) - append to file safely
cat > "$SECRETS_FILE" <<EOF
# DEV SECRETS (developer-only)

VNC_USER: $VNC_USER
VNC_PASSWORD: $VNC_PASS
VNC_DISPLAY: :1
VNC_PORT: 5901
SSH_USER: $VNC_USER
SSH_PORT: 22
SSH_PUBLIC_KEYS_PRESENT: $( [ -f "$VNC_HOME/.ssh/authorized_keys" ] && echo 'yes' || echo 'no' )

# Notes: Do NOT commit this file to public repos. Keep it in a secure vault in production.
EOF
chmod 600 "$SECRETS_FILE"
chown "$VNC_USER:$VNC_USER" "$SECRETS_FILE" || true

echo "=== Host setup completed. Secrets file: $SECRETS_FILE ==="
cat "$SECRETS_FILE"

echo "Next: run the client script on your Linux client to generate/print the public key and create an SSH tunnel."
exit 0
