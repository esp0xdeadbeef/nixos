#!/usr/bin/env bash
# Keep the s-nodus boot card's firmware in step with the flake -- without
# rewriting it when nothing changed.
#
# THE PROBLEM THIS SOLVES
# -----------------------
# nixos-rebuild cannot reach the firmware:
#
#   nixos-rebuild switch  ->  /nix, /etc, ESP (mmcblk0p5)
#                         x   FIP   (mmcblk0p4)   BL31 + U-Boot
#                         x   BL2   (raw sector 34)
#
# so a rebuilt BL31 sits in the store and never reaches the card.  But the
# obvious fix -- unconditionally dd the FIP on every build -- is worse than
# the disease: it rewrites the bootloader on every switch, and one torn write
# costs a physical card pull.
#
# WHAT IT DOES INSTEAD
# --------------------
# A checksum manifest on the ESP records what is currently ON THE CARD:
#
#   /boot/firmware-installed.sha256
#
# The script compares that against the checksums of the freshly built
# artifacts and writes ONLY what differs.  If nothing changed, it writes
# nothing and exits 0.  Writes are per-tier, so installing a new BL31 never
# touches BL2.
#
# ORDER: FIP before BL2.
#   * a bad FIP is recoverable -- BL2 is intact and the old FIP can be written
#     back over the network;
#   * a bad BL2 needs the card physically pulled.
#
# USAGE
#   sudo ./sync-firmware.sh              # apply whatever differs
#   sudo ./sync-firmware.sh --check      # report drift, write nothing (exit 1 if drift)
#   sudo ./sync-firmware.sh --force-fip  # rewrite the FIP even if the sums match
#   sudo ./sync-firmware.sh --fip-only   # BL31/U-Boot only (SAFE default in practice:
#                                       #   BL2 needs the card pulled if it is wrong)
#   sudo ./sync-firmware.sh --bl2-only   # risky; only for a BL2 known to boot
#   sudo ./sync-firmware.sh --adopt      # record what is on the card as current,
#                                        # e.g. after a hand-flash, to stop drift
set -euo pipefail

FLAKE=${FLAKE:-/home/deadbeef/github/nixos}
ATTR=".#nixosConfigurations.s-nodus.config"
DEV=${DEV:-/dev/mmcblk0}
MANIFEST=/boot/firmware-installed.sha256

BL2_SECTOR=34
BL2_SECTORS=8158 # 34..8191, same geometry as mk-sd-image.sh
FIP_PARTLABEL=fip

CHECK=0
FORCE_FIP=0
ADOPT=0
ONLY_FIP=0
ONLY_BL2=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --force-fip) FORCE_FIP=1 ;;
    --fip-only) ONLY_FIP=1 ;;
    --bl2-only) ONLY_BL2=1 ;;
    --adopt) ADOPT=1 ;;
    -h | --help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
die() {
  echo "!! $*" >&2
  exit 1
}

# --- the manifest ---------------------------------------------------------
# Two lines, `<sha256>  <tier>`.  Missing file means "unknown", which is NOT
# the same as "clean": we resolve it by reading the card.

manifest_get() {
  [ -f "$MANIFEST" ] || return 1
  awk -v k="$1" '$2==k {print $1}' "$MANIFEST" | head -1
}

manifest_set() { # tier sha
  local tmp
  tmp=$(mktemp)
  if [ -f "$MANIFEST" ]; then
    awk -v k="$1" '$2!=k' "$MANIFEST" >"$tmp" || true
  fi
  printf '%s  %s\n' "$2" "$1" >>"$tmp"
  sort -k2 "$tmp" -o "$tmp"
  cat "$tmp" >"$MANIFEST"
  rm -f "$tmp"
}

# --- what is actually on the card ----------------------------------------
card_fip_sha() {
  local d
  d=$(readlink -f "/dev/disk/by-partlabel/$FIP_PARTLABEL" 2>/dev/null) || return 1
  # only hash as much as the built FIP needs; the rest is unused tail
  local n=${1:-0}
  if [ "$n" -gt 0 ]; then
    head -c "$n" "$d" | sha256sum | cut -d' ' -f1
  else
    sha256sum "$d" | cut -d' ' -f1
  fi
}

# Hash only as many bytes as the image we are comparing against.  The BL2
# *partition* is 8158 sectors (~4 MiB) but bl2.img is ~250 KiB, so hashing the
# whole partition never matches the built file -- that produced a false
# "readback MISMATCH" on a write that was actually correct.
card_bl2_sha() {
  local n=${1:-}
  if [ -n "$n" ]; then
    dd if="$DEV" bs=512 skip="$BL2_SECTOR" status=none | head -c "$n" | sha256sum | cut -d' ' -f1
  else
    dd if="$DEV" bs=512 skip="$BL2_SECTOR" count="$BL2_SECTORS" status=none |
      sha256sum | cut -d' ' -f1
  fi
}

# --- resolve the built firmware ------------------------------------------
say ">> resolving firmware from the flake"
# These are system.build.* outputs (see nixos-hardware fip.nix), not
# hardware.bananapi.* options: BL2 is a bare file and the FIP is assembled by
# fiptool from BL31 + U-Boot.
# The board is a router, not a builder: BL31 + U-Boot from source with
# max-jobs=2 takes tens of minutes.  The fleet's builders already hold these
# outputs, so ask them first and only build locally if nobody has them.
#
# `--builders` is passed explicitly because the running generation's
# /etc/nix/nix.conf predates the remote-builder-client module, so the board
# currently has no builders line at all.
BUILDERS=${S_NODUS_BUILDERS:-"ssh-ng://s-tau-builder aarch64-linux,x86_64-linux - 8 2 big-parallel,kvm,nixos-test; ssh-ng://s-sigma-builder aarch64-linux,x86_64-linux - 8 2 big-parallel,kvm,nixos-test"}

nix_build() {
  nix build --impure --no-link --print-out-paths \
    --option builders "$BUILDERS" \
    --option builders-use-substitutes true \
    --option fallback true \
    "$@"
}

ATF_OUT=$(nix_build "$ATTR.hardware.bananapi.bpi-r4-pro.atfPackage")
FIP_OUT=$(nix_build "$ATTR.system.build.bpiR4ProFip")

BL2_IMG="$ATF_OUT/bl2.img"
[ -f "$BL2_IMG" ] || die "no bl2.img in $ATF_OUT"

# system.build.bpiR4ProFip is a runCommand whose *output is the FIP file
# itself* (see fip.nix: `fiptool create ... "$out"`), not a directory.
if [ -f "$FIP_OUT" ]; then
  FIP_IMG="$FIP_OUT"
else
  FIP_IMG=$(find "$FIP_OUT" -maxdepth 1 -type f \( -name '*.fip' -o -name 'fip*' \) | head -1)
fi
[ -n "$FIP_IMG" ] && [ -f "$FIP_IMG" ] || die "no fip image from $FIP_OUT"

BL2_SUM=$(sha256sum "$BL2_IMG" | cut -d' ' -f1)
FIP_SUM=$(sha256sum "$FIP_IMG" | cut -d' ' -f1)
say "   bl2 $BL2_SUM  $BL2_IMG"
say "   fip $FIP_SUM  $FIP_IMG ($(stat -c%s "$FIP_IMG") B)"

# --- what do we think is installed? --------------------------------------
# Prefer the recorded manifest; fall back to hashing the card so a missing or
# stale marker never causes a needless rewrite.
if REC_BL2=$(manifest_get bl2) && [ -n "$REC_BL2" ]; then
  say ">> recorded bl2: $REC_BL2"
else
  REC_BL2=$(card_bl2_sha) || REC_BL2=""
  say ">> no manifest; read bl2 from card: ${REC_BL2:-<unreadable>}"
fi

if REC_FIP=$(manifest_get fip) && [ -n "$REC_FIP" ]; then
  say ">> recorded fip: $REC_FIP"
else
  REC_FIP=$(card_fip_sha "$(stat -c%s "$FIP_IMG")") || REC_FIP=""
  say ">> no manifest; read fip from card: ${REC_FIP:-<unreadable>}"
fi

# --- decide --------------------------------------------------------------
NEED_BL2=0
NEED_FIP=0
[ "$REC_BL2" = "$BL2_SUM" ] || NEED_BL2=1
[ "$REC_FIP" = "$FIP_SUM" ] || NEED_FIP=1
[ "$FORCE_FIP" -eq 1 ] && NEED_FIP=1

# --fip-only / --bl2-only restrict the write set.  BL2 must be written alone
# unless it has been PROVEN to boot: it is the one tier whose failure cannot
# be recovered without physically pulling the card.  Writing it as a side
# effect of "the FIP changed" bricked this board once already.
if [ "$ONLY_FIP" -eq 1 ] && [ "$ONLY_BL2" -eq 1 ]; then
  die "--fip-only and --bl2-only are mutually exclusive"
fi
[ "$ONLY_FIP" -eq 1 ] && NEED_BL2=0
[ "$ONLY_BL2" -eq 1 ] && NEED_FIP=0

if [ "$ADOPT" -eq 1 ]; then
  [ "$(id -u)" -eq 0 ] || die "--adopt writes to $MANIFEST; run as root"
  manifest_set bl2 "$(card_bl2_sha "$(stat -c%s "$BL2_IMG")")"
  manifest_set fip "$(card_fip_sha "$(stat -c%s "$FIP_IMG")")"
  say ">> adopted current card contents as installed"
  exit 0
fi

if [ "$NEED_BL2" -eq 0 ] && [ "$NEED_FIP" -eq 0 ]; then
  say ">> firmware already current; nothing to write"
  exit 0
fi

[ "$NEED_BL2" -eq 1 ] && say ">> BL2 differs (card ${REC_BL2:-unknown})"
[ "$NEED_FIP" -eq 1 ] && say ">> FIP differs (card ${REC_FIP:-unknown})"

if [ "$CHECK" -eq 1 ]; then
  say ">> --check: drift detected, nothing written"
  exit 1
fi

[ "$(id -u)" -eq 0 ] || die "must run as root to write $DEV"
[ -b "$DEV" ] || die "$DEV is not a block device"

# --- write the FIP first -------------------------------------------------
if [ "$NEED_FIP" -eq 1 ]; then
  FIP_TARGET=$(readlink -f "/dev/disk/by-partlabel/$FIP_PARTLABEL" 2>/dev/null) ||
    die "no partition labelled '$FIP_PARTLABEL'; BL2 looks the FIP up by GPT name"
  NEED=$(stat -c%s "$FIP_IMG")
  AVAIL=$(blockdev --getsize64 "$FIP_TARGET")
  [ "$NEED" -le "$AVAIL" ] || die "FIP ($NEED B) does not fit $FIP_TARGET ($AVAIL B)"

  say ">> writing FIP -> $FIP_TARGET"
  dd if="$FIP_IMG" of="$FIP_TARGET" bs=1M conv=fsync status=none
  sync

  say ">> verifying FIP readback"
  cmp -s -n "$NEED" "$FIP_IMG" "$FIP_TARGET" ||
    die "FIP readback MISMATCH -- do not reboot; re-run this script"
  say "   OK"
  manifest_set fip "$FIP_SUM"
fi

# --- then BL2, last ------------------------------------------------------
if [ "$NEED_BL2" -eq 1 ]; then
  say ">> writing BL2 -> $DEV sector $BL2_SECTOR"
  dd if="$BL2_IMG" of="$DEV" bs=512 seek="$BL2_SECTOR" conv=fsync status=none
  sync

  say ">> verifying BL2 readback"
  BL2_SIZE=$(stat -c%s "$BL2_IMG")
  NOW=$(card_bl2_sha "$BL2_SIZE")
  [ "$NOW" = "$BL2_SUM" ] ||
    die "BL2 readback MISMATCH (got $NOW) -- the card may not boot"
  say "   OK"

  MAGIC=$(dd if="$DEV" bs=1 skip=$((BL2_SECTOR * 512)) count=11 status=none | tr -d '\0')
  [ "$MAGIC" = "SDMMC_BOOT" ] || say "   warning: magic at sector 34 is '$MAGIC', expected SDMMC_BOOT"
  manifest_set bl2 "$BL2_SUM"
fi

say ""
say "firmware updated.  Manifest: $MANIFEST"
say ""
say "Before rebooting, start a durable console log -- a boot that never"
say "reaches Linux writes nothing to the journal:"
say ""
say "  tio /dev/ttyACM0 -b 115200 | tee -a /var/log/s-nodus-console.log"
say ""
say "then check every handoff:"
say "  ./bootproof.sh /var/log/s-nodus-console.log"
