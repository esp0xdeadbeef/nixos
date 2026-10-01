#!/usr/bin/env bash
# One-shot: build the s-nodus NixOS SD image and write it to a card.
#
# This is the single entry point.  It:
#   1. builds the firmware blobs (BL2 + ARM-TF FIP) from the vendor image,
#   2. builds the NixOS FIT + btrfs root and assembles the full GPT image,
#   3. writes it raw to the card from sector 0 and grows the root.
#
# Run as root (or with sudo).  DESTRUCTIVE: the target device is wiped.
#
# USAGE
#   sudo ./flash-s-nodus.sh [DEVICE] [VENDOR_IMG]
#
# Defaults:
#   DEVICE      /dev/sda
#   VENDOR_IMG  the newest BPI-R4Pro-...-sdcard-*.img under the invoker's
#               ~/Downloads (the vendor OpenWrt SD image; source of BL2/FIP)
set -euo pipefail

DEV="${1:-/dev/sda}"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -n "${2:-}" ]; then
  VENDOR_IMG="$2"
else
  # Resolve the invoker's home, not root's ($HOME is /root under sudo).
  USER_HOME="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)"
  [ -n "$USER_HOME" ] || USER_HOME="$HOME"
  VENDOR_IMG="$(find "$USER_HOME/Downloads" -type f -name '*BPI-R4Pro*sdcard*.img' 2>/dev/null | sort | tail -1)"
fi

[ -r "$VENDOR_IMG" ] || {
  echo "!! vendor donor image not found; pass it as arg 2"
  echo "   (expected e.g. BPI-R4Pro-4E-BE14-MT76-OpenWRT24.10-sdcard-*.img)"
  exit 1
}
[ -b "$DEV" ] || { echo "!! $DEV is not a block device"; exit 1; }

echo ">> target device : $DEV"
lsblk -o NAME,SIZE,MODEL,TRAN "$DEV" | sed 's/^/   /'
echo ">> vendor donor  : $VENDOR_IMG"
echo

"$HERE/mk-sd-image.sh" build "$VENDOR_IMG"
"$HERE/mk-sd-image.sh" flash "$DEV"

echo
echo ">> DONE. Power-cycle the board (cold boot, boot switch = SD) and watch"
echo "   the serial console at 115200 8N1 on ttyS0."
