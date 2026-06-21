#!/usr/bin/env nix-shell
#!nix-shell -i bash -p clevis cryptsetup curl coreutils util-linux

set -euo pipefail

TANG_URL="http://192.168.1.75:7500"
LUKS_DEV="/dev/disk/by-partlabel/disk-nvme0n1-luks"
JWE_OUT="./root.jwe"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root" >&2
  exit 1
fi

if [[ ! -b "$LUKS_DEV" ]]; then
  echo "LUKS device not found: $LUKS_DEV" >&2
  exit 1
fi

echo "Checking Tang advertisement..."
curl -fsS "$TANG_URL/adv" >/dev/null

echo
read -r -s -p "Enter CURRENT LUKS passphrase: " EXISTING_LUKS_PASS
echo

if [[ -z "$EXISTING_LUKS_PASS" ]]; then
  echo "Empty passphrase not allowed" >&2
  exit 1
fi

cleanup() {
  unset EXISTING_LUKS_PASS CLEVIS_PASS
}
trap cleanup EXIT

CLEVIS_PASS="$(head -c 32 /dev/urandom | base64)"

printf '%s' "$CLEVIS_PASS" \
  | clevis encrypt tang "{\"url\":\"$TANG_URL\"}" -y \
  > "$JWE_OUT"

printf '%s' "$EXISTING_LUKS_PASS" \
  | cryptsetup luksAddKey "$LUKS_DEV" \
    --key-file - \
    <(printf '%s' "$CLEVIS_PASS")

printf '%s' "$CLEVIS_PASS" \
  | cryptsetup open --test-passphrase "$LUKS_DEV"

echo "Clevis key added and verified"
echo "JWE stored at: $JWE_OUT"
