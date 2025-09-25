#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

HOST="$1"

echo "[*] Checking uptime on $HOST..."
ssh "deadbeef@$HOST" uptime || { echo "❌ SSH to $HOST failed"; sleep 2; exit 1; }

echo "[*] Running rsync to $HOST..."
if timeout 3 rsync -va --exclude='.git' /home/deadbeef/github/nixos "deadbeef@$HOST:~/github/" | grep -q "nixos/$HOST/"; then
  echo "[*] Changes detected, rebuilding and rebooting $HOST..."
  if [[ "$HOST" == "s-router-vpn-1" ]]; then
    ( ssh "deadbeef@$HOST" 'sudo nmcli connection down tun0' ) || true
  fi
  ssh "deadbeef@$HOST" 'sudo nixos-rebuild boot --impure --flake path:/home/deadbeef/github/nixos#$(hostname) --no-write-lock-file' \
    && ssh "deadbeef@$HOST" 'sudo reboot' \
    && echo "[*] Rebooting $HOST..." \
    && sleep 20
else
  echo "[*] No changes, sleeping"
  sleep 2
fi
