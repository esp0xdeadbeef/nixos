#!/usr/bin/env bash
# Bisect BL2 vs FIP on the s-nodus card.
#   ./apply-variant.sh A   vendor BL2 + our FIP     -> boots?  then OUR BL2 is bad
#   ./apply-variant.sh B   our BL2   + vendor FIP   -> boots?  then OUR FIP is bad
#   ./apply-variant.sh C   vendor BL2 + vendor FIP  -> control: must boot (OpenWrt)
#   ./apply-variant.sh O   our BL2   + our FIP      -> the failing combination
set -euo pipefail
DEV=${2:-/dev/sda}
D=$(cd "$(dirname "$0")" && pwd)
case "${1:?usage: $0 A|B|C|O [device]}" in
  A) BL2=vendor-bl2.img; FIP=our-fip.img;    ;;
  B) BL2=our-bl2.img;    FIP=vendor-fip.img; ;;
  C) BL2=vendor-bl2.img; FIP=vendor-fip.img; ;;
  O) BL2=our-bl2.img;    FIP=our-fip.img;    ;;
  *) echo "unknown variant $1" >&2; exit 1 ;;
esac
echo "variant $1: BL2=$BL2 FIP=$FIP -> $DEV"
dd if="$D/$BL2" of="$DEV" bs=512 seek=34    conv=fsync status=none
dd if="$D/$FIP" of="$DEV" bs=512 seek=13312 conv=fsync status=none
sync
echo -n "bl2: "; dd if="$DEV" bs=512 skip=34    count=1 status=none | head -c 11; echo
echo -n "fip: "; dd if="$DEV" bs=512 skip=13312 count=1 status=none | od -An -tx1 -N4
