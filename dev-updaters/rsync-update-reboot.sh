#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <hostname>"
  exit 1
fi

sleep 1

HOST="$1"
USER="deadbeef"
SSH="$USER@$HOST"
SRC="$HOME/github/nixos/"
DST="$SSH:~/github/nixos/"

echo "[*] Checking uptime on $HOST..."
ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH" uptime

echo "[*] Syncing repo to $HOST..."
RSYNC_OUT=$(rsync -a --delete --itemize-changes --exclude='.git' "$SRC" "$DST")

# --- Host-specific path patterns ---
HOST_REGEX=""
case "$HOST" in
  s-router-core)
    HOST_REGEX='^.*nixos/s-routers/1-core/'
    ;;
  s-router-edge)
    HOST_REGEX='^.*nixos/s-routers/2-edge/'
    ;;
  s-router-access)
    HOST_REGEX='^.*nixos/s-routers/3-access/'
    ;;
  s-router-vpn-egress)
    HOST_REGEX='^.*nixos/s-routers/z-vpn-egress/'
    ;;
  s-*)
    HOST_REGEX="^.*$HOST.*"
    ;;
  l-*)
    HOST_REGEX="^.*$HOST.*"
    ;;
  *)
    echo "❌ Unknown host layout for $HOST"
    exit 1
    ;;
esac

# --- Shared paths affecting all hosts ---
SHARED_REGEX='^.*(flake\.nix|flake\.lock|modules/|overlays/).*'

# --- Relevant file types ---
FILE_REGEX='\.nix$|\.nft$|\.yaml$'
#echo $RSYNC_OUT
#echo $FILE_REGEX
#echo $HOST_REGEX
#echo $SHARED_REGEX
if echo "$RSYNC_OUT" | awk '{print $2}' | grep -E "$FILE_REGEX" | grep -E "$HOST_REGEX|$SHARED_REGEX" >/dev/null; then
  echo "[*] Relevant changes detected for $HOST"

  if [[ "$HOST" == "s-router-vpn-1" ]]; then
    echo "[*] Bringing down VPN"
    ssh "$SSH" 'sudo nmcli connection down tun0' || true
  fi

  echo "[*] Rebuilding on $HOST..."
  ssh "$SSH" \
    'sudo nixos-rebuild boot --impure --flake path:/home/deadbeef/github/nixos#$(hostname) --no-write-lock-file'

  echo "[*] Rebooting $HOST..."
  ssh "$SSH" 'sudo reboot'
else
  echo "[*] No relevant changes for $HOST"
fi

