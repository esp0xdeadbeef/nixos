#!/usr/bin/env nix-shell
#!nix-shell -i bash -p clevis cryptsetup curl coreutils util-linux

set -euo pipefail

###############################################################################
# Configuration
###############################################################################
TANG_HOST="${TANG_HOST:-192.168.1.75}"
TANG_PORT="${TANG_PORT:-7500}"
TANG_URL="${TANG_URL:-http://${TANG_HOST}:${TANG_PORT}}"
LUKS_DEV="/dev/disk/by-partlabel/disk-root-luks"
JWE_OUT="/tmp/nvme0n1p1.jwe"

###############################################################################
# Sanity checks
###############################################################################
if [[ $EUID -ne 0 ]]; then
  echo "❌ Run as root" >&2
  exit 1
fi

if [[ ! -b "$LUKS_DEV" ]]; then
  echo "❌ LUKS device not found: $LUKS_DEV" >&2
  exit 1
fi

echo "🔎 Checking Tang advertisement..."
curl -fsS "$TANG_URL/adv" >/dev/null
echo "✅ Tang server reachable"

###############################################################################
# PROMPT FOR EXISTING LUKS PASSPHRASE (THIS WAS MISSING)
###############################################################################
echo
read -s -p "🔑 Enter CURRENT LUKS passphrase: " EXISTING_LUKS_PASS
echo

if [[ -z "$EXISTING_LUKS_PASS" ]]; then
  echo "❌ Empty passphrase not allowed" >&2
  exit 1
fi

###############################################################################
# Generate new Clevis secret
###############################################################################
cleanup() {
  unset EXISTING_LUKS_PASS CLEVIS_PASS
}
trap cleanup EXIT

CLEVIS_PASS="$(head -c 32 /dev/urandom | base64)"

###############################################################################
# Create JWE
###############################################################################
echo "🔐 Creating Clevis JWE..."
printf '%s' "$CLEVIS_PASS" | \
  clevis encrypt tang "{\"url\":\"$TANG_URL\"}" -y \
  > "$JWE_OUT"
echo "✅ JWE written to $JWE_OUT"

###############################################################################
# ADD NEW KEY — EXPLICIT AUTH + EXPLICIT NEW KEY
###############################################################################
echo "🔑 Adding new LUKS keyslot using provided passphrase..."

printf '%s' "$EXISTING_LUKS_PASS" | \
  cryptsetup luksAddKey "$LUKS_DEV" \
    --key-file - \
    <(printf '%s' "$CLEVIS_PASS")

echo "✅ New keyslot added"

###############################################################################
# VERIFY NEW KEY
###############################################################################
echo "🧪 Verifying new Clevis key works..."

printf '%s' "$CLEVIS_PASS" | \
  cryptsetup open --test-passphrase "$LUKS_DEV"

echo "🎉 SUCCESS: Clevis key added and verified"
echo "📄 JWE stored at: $JWE_OUT"
