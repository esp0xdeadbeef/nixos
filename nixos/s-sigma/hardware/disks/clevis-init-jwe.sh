#!/usr/bin/env bash
set -euo pipefail

TANG_URL="http://192.168.1.75:7500"
LUKS_DEV="/dev/disk/by-partlabel/disk-root-luks"

# Generate random password for Clevis
CLEVIS_PASS=$(head -c 32 /dev/urandom | base64)

# Add as new LUKS keyslot (will prompt for your existing passphrase)
cryptsetup luksAddKey "$LUKS_DEV" <(echo -n "$CLEVIS_PASS")

# Create JWE with the random password
echo -n "$CLEVIS_PASS" | clevis encrypt tang "{\"url\":\"$TANG_URL\"}" > /tmp/nvme0n1p1.jwe

# Verify (exit code must be 0):
clevis decrypt < /tmp/nvme0n1p1.jwe | cryptsetup open --test-passphrase "$LUKS_DEV" && echo "✅ works"

# Clear variable
unset CLEVIS_PASS

echo "JWE created at /tmp/nvme0n1p1.jwe"

