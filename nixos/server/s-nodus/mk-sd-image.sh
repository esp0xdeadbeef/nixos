#!/usr/bin/env bash
# Build a complete, bootable microSD image for s-nodus (Banana Pi BPI-R4 Pro 4E)
# and flash it to a card.
#
# WHY THIS EXISTS
# ---------------
# The MT7988 BootROM, MediaTek BL2 and the board's stock OpenWrt U-Boot locate
# their payloads by *fixed sector offsets* and by GPT *partition name*, and
# they need signed firmware (BL2 + ARM-TF FIP) that disko cannot write.  disko
# alone can lay down the GPT and the btrfs root, but not:
#   * the BL2 blob at sector 34 (the BootROM loads it from raw sector 34);
#   * the FIP blob in the partition named `fip` (BL2 fails with
#     "Partition 'fip' not found" -> "System halt!" without it);
#   * the NixOS FIT, raw at offset 0 of the partition named `production`
#     (the stock U-Boot's boot_production reads it from there).
#
# This script assembles the whole disk.  Layout (matches the vendor GPT):
#
#   #  name        start(sec)  size         type   contents
#   1  bl2               34    8158  (~4M)   Linux  MTK BL2        (firmware.nix)
#   2  ubootenv        8192    1024  (512K)  Linux  (zeros)
#   3  factory         9216    4096  (2M)    Linux  (zeros)
#   4  fip            13312    8192  (4M)    EFI    ARM-TF FIP     (firmware.nix)
#   5  production    327680  917504  (448M)  Linux  NixOS FIT      (built here)
#   6  nixos-root   1245184   <fills>         Linux  btrfs root     (built here)
#
# ubootenv/factory are all-zero in the vendor image (U-Boot uses its built-in
# env), so they are left as zeros -- the GPT entries still exist because the
# boot chain looks some of them up by name.
#
# ROOT FILESYSTEM LAYOUT
# ----------------------
# The running system's fileSystems (./disko.nix) are:
#
#   /        -> subvol=/root      root=PARTLABEL=nixos-root rootflags=subvol=/root
#   /nix     -> subvol=/nix
#   /persist -> subvol=/persist   (impermanence)
#
# so the card's nixos-root MUST contain those three subvolumes, with the store
# closure under /nix and the toplevel under /root.  The sdImage rootfs image is
# a FLAT btrfs; we therefore build the card's filesystem here (mkfs + subvolume
# create + populate), running as root on this host.  Nothing is executed from
# the aarch64 closure, so this works fine on x86_64.
#
# USAGE
#   ./mk-sd-image.sh build [VENDOR_IMG]   # assemble the image
#   ./mk-sd-image.sh flash <device>       # write image to a card + grow root
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo "$HERE/../../..")"
WORK=/tmp/bpi-r4/sdimg
IMG="$WORK/s-nodus-sd.img"

# Fixed geometry (512-byte sectors) -- must match disko.nix and the vendor GPT.
P1_S=34;       P1_N=8158               # bl2
P2_S=8192;     P2_N=1024               # ubootenv
P3_S=9216;     P3_N=4096               # factory
P4_S=13312;    P4_N=8192               # fip
P5_S=327680;   P5_N=917504             # production (raw FIT)
P6_S=1245184                           # nixos-root

DISK_GUID="5452574F-2211-4433-5566-778899AABB00"
U1="5452574F-2211-4433-5566-778899AABB01"
U2="5452574F-2211-4433-5566-778899AABB02"
U3="5452574F-2211-4433-5566-778899AABB03"
U4="5452574F-2211-4433-5566-778899AABB04"
U5="5452574F-2211-4433-5566-778899AABB05"
U6="FA68B5BF-67F7-434C-B7C1-1D078578A2C3"

resolve_sgdisk() {
  if command -v sgdisk >/dev/null 2>&1; then
    command -v sgdisk
  else
    nix shell nixpkgs#gptfdisk -c sh -c 'command -v sgdisk'
  fi
}
SGDISK="$(resolve_sgdisk)"
[ -x "$SGDISK" ] || { echo "!! could not resolve sgdisk"; exit 1; }

find_vendor_img() {
  local home; home="$(getent passwd "${SUDO_USER:-$(id -un)}" | cut -d: -f6)"
  [ -n "$home" ] || home="$HOME"
  find "$home/Downloads" -type f -name '*BPI-R4Pro*sdcard*.img' 2>/dev/null | sort | tail -1
}

build() {
  local VENDOR_IMG="${1:-}"
  [ -n "$VENDOR_IMG" ] || VENDOR_IMG="$(find_vendor_img)"
  [ -r "$VENDOR_IMG" ] || { echo "!! vendor image not found; pass it: $0 build <vendor.img>"; exit 1; }
  mkdir -p "$WORK"
  echo ">> vendor donor: $VENDOR_IMG"

  echo ">> building firmware blobs (firmware.nix)"
  local FW
  FW=$(nix-build --no-out-link -E "
    let pkgs = import <nixpkgs> { system = builtins.currentSystem; };
    in pkgs.callPackage $HERE/firmware.nix { vendorImagePath = $VENDOR_IMG; }")
  echo "   firmware = $FW"

  echo ">> building NixOS FIT for s-nodus"
  local FIT
  FIT=$(nix build --builders '' --print-out-paths --no-link \
    "$REPO#nixosConfigurations.s-nodus.config.system.build.bpiR4ProFit")
  echo "   FIT = $FIT ($(stat -c%s "$FIT") bytes)"

  echo ">> building rootfs (flat btrfs image with the store closure)"
  local ROOT
  ROOT=$(nix build --builders '' --print-out-paths --no-link \
    "$REPO#nixosConfigurations.s-nodus.config.system.build.rootfsImage")
  echo "   rootfs = $ROOT"

  local fsz; fsz=$(stat -c%s "$FIT")
  if [ "$fsz" -gt $(( P5_N * 512 )) ]; then
    echo "!! FIT ($fsz B) exceeds production partition ($(( P5_N * 512 )) B)"; exit 1
  fi

  # The rootfs image is FLAT and only as large as its content; on the card we
  # mkfs a bigger nixos-root and lay down the subvolumes ourselves.  Size the
  # compact image to hold rootfs content + growth headroom.
  local rn p6e total
  rn=$(( $(stat -L -c%s "$ROOT") / 512 ))
  p6e=$(( P6_S + rn - 1 ))
  total=$(( p6e + 34 ))
  echo ">> assembling $IMG (root=$rn sec, total=$total sec = $(( total/2/1024 )) MiB)"
  rm -f "$IMG"
  truncate -s $(( total * 512 )) "$IMG"

  # -a 1: no 2048-sector alignment -- the firmware partitions sit at exact
  # offsets that BL2's GPT scan and the BootROM locate by raw sector.
  "$SGDISK" -Z "$IMG" >/dev/null
  "$SGDISK" -U "$DISK_GUID" "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 1:$P1_S:$(( P1_S+P1_N-1 )) -t 1:8300 -c 1:bl2        -u 1:$U1 "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 2:$P2_S:$(( P2_S+P2_N-1 )) -t 2:8300 -c 2:ubootenv   -u 2:$U2 "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 3:$P3_S:$(( P3_S+P3_N-1 )) -t 3:8300 -c 3:factory    -u 3:$U3 "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 4:$P4_S:$(( P4_S+P4_N-1 )) -t 4:ef00 -c 4:fip        -u 4:$U4 "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 5:$P5_S:$(( P5_S+P5_N-1 )) -t 5:8300 -c 5:production -u 5:$U5 "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 6:$P6_S:0                  -t 6:8300 -c 6:nixos-root -u 6:$U6 "$IMG" >/dev/null
  # Vendor GPT attribute flags (RequiredPartition / LegacyBIOSBootable).
  "$SGDISK" -A 1:set:0 -A 1:set:2 -A 2:set:0 -A 3:set:0 -A 4:set:0 "$IMG" >/dev/null

  echo ">> writing payloads"
  dd if="$FW/bl2.bin"  of="$IMG" bs=512 seek=$P1_S conv=notrunc status=none
  dd if="$FW/fip.bin"  of="$IMG" bs=512 seek=$P4_S conv=notrunc status=none
  dd if="$FIT"         of="$IMG" bs=512 seek=$P5_S conv=notrunc status=none

  # Write the btrfs root with the subvolumes the boot expects.  Loop-mount the
  # freshly written GPT partition, so the subvolume layout is exactly right.
  echo ">> creating subvolumes + populating root (needs root)"
  _populate_root_in_image "$IMG" "$ROOT"

  # Write the U-Boot environment.  This is MANDATORY: U-Boot's
  # image_setup_libfdt() always overwrites /chosen/bootargs with
  # env_get("bootargs"), so the FIT's bootargs are ignored and the vendor
  # default (root=/dev/fit0) cannot boot NixOS.  See uboot-env.txt.
  echo ">> writing U-Boot environment (ubootenv partition)"
  _write_uboot_env_in_image "$IMG"

  local got
  got=$(dd if="$IMG" bs=512 skip=$P4_S count=1 status=none | od -An -tx1 | tr -d ' \n')
  [ "${got:0:8}" = "010064aa" ] || { echo "!! FIP header not at fip start"; exit 1; }
  got=$(dd if="$IMG" bs=512 skip=$P5_S count=1 status=none | od -An -tx1 | tr -d ' \n')
  [ "${got:0:8}" = "d00dfeed" ] || { echo "!! FIT magic not at production start"; exit 1; }
  echo "   verified: fip header + production FIT magic"

  echo ">> built $IMG ($(du -h "$IMG" | cut -f1))"
  echo "   flash with: $0 flash <device>"
}

# Create mkfs.btrfs + the /root,/nix,/persist subvolumes inside the image, then
# copy the flat rootfs contents into place.  ROOT is a raw btrfs *image* (not a
# directory), so it is loop-mounted read-only as the content source.
_populate_root_in_image() {
  local IMG="$1" ROOT="$2"
  local m="/tmp/bpi-r4/img-root" src="/tmp/bpi-r4/img-src" top="/tmp/bpi-r4/img-top"
  # Clean any leftovers from a previous interrupted run before reusing paths.
  sudo umount -R "$m" 2>/dev/null || true
  sudo umount -R "$src" 2>/dev/null || true
  sudo umount -R "$top" 2>/dev/null || true
  rm -rf "$m" "$src" "$top"; mkdir -p "$m" "$src" "$top"

  # Source: the flat rootfs image (contains nix/store + nix-path-registration).
  sudo mount -o ro,loop "$ROOT" "$src"
  # Attach the target image's nixos-root partition as a loop device.
  local part=""
  part=$(sudo losetup --show -f -P --offset $(( P6_S * 512 )) "$IMG")
  # shellcheck disable=SC2064  # expand now: locals may be gone when the trap runs
  trap "sudo umount -R '$m' 2>/dev/null || true; sudo umount -R '$src' 2>/dev/null || true; sudo umount -R '$top' 2>/dev/null || true; sudo losetup -d '$part' 2>/dev/null || true" RETURN

  sudo mkfs.btrfs -q -f -L nixos-root "$part"

  # Create the three subvolumes the boot expects (see file header).
  sudo mount "$part" "$top"
  sudo btrfs subvolume create "$top/root" >/dev/null
  sudo btrfs subvolume create "$top/nix" >/dev/null
  sudo btrfs subvolume create "$top/persist" >/dev/null
  sudo umount "$top"

  # /nix subvolume gets the store closure (+ the registration file).
  # chown -R 0:0: the flat rootfs image is built by the unprivileged nix build
  # user, so every store path arrives owned by that uid.  A store that is not
  # root-owned breaks logrotate's owner check, systemd-tmpfiles' "unsafe path
  # transition" guard, sudo/NSS, etc.  We are already root here, so fix it.
  sudo mount -o subvol=/nix "$part" "$m"
  sudo mkdir -p "$m/store"
  sudo cp -a "$src/nix/store/." "$m/store/"
  sudo chown -R 0:0 "$m/store"
  sudo chmod -R u+w "$m/store"
  sudo chmod 1775 "$m/store"
  sudo umount "$m"

  # /root subvolume gets the rest of the root (nix-path-registration, and
  # anything else the image carries) plus an empty /nix mountpoint.
  sudo mount -o subvol=/root "$part" "$m"
  sudo mkdir -p "$m/nix"
  for f in "$src"/*; do
    case "$(basename "$f")" in
      nix) : ;;   # /nix is the separate subvolume, not this
      *) sudo cp -a "$f" "$m/" ;;
    esac
  done
  sudo chown -R 0:0 "$m"
  sudo umount "$m"
  sudo umount "$src"
  sudo umount -R "$top" 2>/dev/null || true
  sudo losetup -d "$part" 2>/dev/null || true

  rm -rf "$m" "$src" "$top" 2>/dev/null || true
}

# Generate and write the U-Boot environment into the ubootenv partition (p2).
#
# U-Boot's image_setup_libfdt() always overwrites /chosen/bootargs with
# env_get("bootargs"), so the FIT's own bootargs are IGNORED and the vendor
# default `root=/dev/fit0` wins -- which cannot boot NixOS.  The env is
# therefore the only place the real cmdline can live.
#
# Layout: CONFIG_ENV_SIZE=0x40000 with a redundant copy at offset 0x40000,
# i.e. two 0x40000 images filling the 0x80000 (512 KiB) partition.
_write_uboot_env_in_image() {
  local IMG="$1"
  local env="$WORK/uboot.env" tmp top
  tmp="$(mktemp)"
  top=$(nix build --builders '' --print-out-paths --no-link \
    "$REPO#nixosConfigurations.s-nodus.config.system.build.toplevel")
  sed "s|@@TOPLEVEL@@|$top|" "$HERE/uboot-env.txt" > "$tmp"

  # mkenvimage writes ONE copy of the given size; write it twice ourselves.
  nix shell nixpkgs#ubootTools -c \
    mkenvimage -s 0x40000 -r -o "$env" "$tmp"
  rm -f "$tmp"

  [ "$(stat -c%s "$env")" -eq 262144 ] || { echo "!! unexpected env size"; exit 1; }

  # Both copies go into the image at the ubootenv partition offset.
  dd if="$env" of="$IMG" bs=4096 seek=$(( P2_S / 8 ))         conv=notrunc status=none
  dd if="$env" of="$IMG" bs=4096 seek=$(( P2_S / 8 + 64 ))    conv=notrunc status=none

  # Verify.
  local a b e
  e=$(sha256sum "$env" | cut -d' ' -f1)
  a=$(dd if="$IMG" bs=4096 skip=$(( P2_S / 8 ))      count=64 status=none | sha256sum | cut -d' ' -f1)
  b=$(dd if="$IMG" bs=4096 skip=$(( P2_S / 8 + 64 )) count=64 status=none | sha256sum | cut -d' ' -f1)
  [ "$a" = "$e" ] && [ "$b" = "$e" ] || { echo "!! ubootenv write mismatch"; exit 1; }
  echo "   env written (2 copies, sha $e)"
}

flash() {
  local DEV="${1:?usage: $0 flash <device>}"
  [ -b "$DEV" ] || { echo "!! $DEV is not a block device"; exit 1; }
  [ -s "$IMG" ] || { echo "!! image not built (run: $0 build)"; exit 1; }
  echo ">> FLASHING $IMG -> $DEV"
  sudo dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
  sync
  # Grow nixos-root (p6) to fill the card, then grow the btrfs filesystem.
  # `sgdisk -e` first moves the backup GPT to the true end of the device.
  sudo "$SGDISK" -e "$DEV" >/dev/null
  sudo "$SGDISK" -a 1 -d 6 -n 6:$P6_S:0 -t 6:8300 -c 6:nixos-root -u 6:$U6 "$DEV" >/dev/null
  sudo partprobe "$DEV" 2>/dev/null || sudo blockdev --rereadpt "$DEV" 2>/dev/null || true
  sleep 2
  local RP="${DEV}6"; [[ "$DEV" == *[0-9] ]] && RP="${DEV}p6"
  local m=/tmp/bpi-r4/flash-root; sudo mkdir -p "$m"
  sudo mount -o subvol=/root "$RP" "$m"
  sudo btrfs filesystem resize max "$m"
  sync; sudo umount "$m"
  echo ">> flashed. layout:"; sudo "$SGDISK" -p "$DEV" | sed -n '1,20p'
}

cmd="${1:-}"; shift || true
case "$cmd" in
  build) build "$@" ;;
  flash) flash "$@" ;;
  *) sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
