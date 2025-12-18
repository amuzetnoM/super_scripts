#!/usr/bin/env bash
# client_setup_auto.sh
# Idempotent client-side helper for Linux (Debian/Ubuntu compatible).
# Usage: bash client_setup_auto.sh <server_user> <server_host> [private_key_path]
# - Generates an ed25519 keypair if no key exists at provided path (default: ~/.ssh/id_ed25519)
# - Prints the public key (so you can copy it to the server's authorized_keys)
# - Optionally attempts ssh-copy-id if password auth is enabled on server

set -euo pipefail
SERVER_USER=${1:-}
SERVER_HOST=${2:-}
KEY_PATH=${3:-$HOME/.ssh/id_ed25519}

if [ -z "$SERVER_USER" ] || [ -z "$SERVER_HOST" ]; then
  echo "Usage: $0 <server_user> <server_host> [private_key_path]"
  exit 2
fi

# Ensure ssh client present
if ! command -v ssh >/dev/null 2>&1; then
  echo "OpenSSH client not found. Install it (apt-get install -y openssh-client)" >&2
  exit 3
fi

# Generate key if needed
if [ ! -f "$KEY_PATH" ]; then
  echo "Generating ed25519 key at $KEY_PATH (no passphrase)..."
  mkdir -p "$(dirname "$KEY_PATH")" && chmod 700 "$(dirname "$KEY_PATH")"
  ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "$USER@$HOSTNAME"
  chmod 600 "$KEY_PATH"
fi

PUBKEY=$(cat "${KEY_PATH}.pub")
echo "Public key (copy this to $SERVER_USER@${SERVER_HOST}:~/.ssh/authorized_keys):"
echo ""
echo "$PUBKEY"
echo ""

# Attempt ssh-copy-id (safe: will fail if password auth disabled)
if command -v ssh-copy-id >/dev/null 2>&1; then
  echo "Attempting ssh-copy-id (will prompt for password if server allows it)..."
  ssh-copy-id -i "${KEY_PATH}.pub" "${SERVER_USER}@${SERVER_HOST}" || echo "ssh-copy-id failed (maybe server disallows password auth). Copy the key manually."
else
  echo "ssh-copy-id not available — copy the key above to the server's ~/.ssh/authorized_keys manually or via cloud console."
fi

# Install a VNC viewer if missing (optional)
if ! command -v vncviewer >/dev/null 2>&1; then
  echo "Installing TigerVNC viewer (apt/yum as available)"
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y tigervnc-viewer || true
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y tigervnc || true
  fi
fi

# Provide the tunnel command
echo "To create the SSH tunnel and connect VNC (run on this client):"
echo "  ssh -i ${KEY_PATH} -L 5901:localhost:5901 ${SERVER_USER}@${SERVER_HOST}"
echo "Then open your VNC viewer and connect to localhost:5901 (enter VNC password)."
exit 0
