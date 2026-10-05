#!/usr/bin/env bash
# Build and flash the s-nodus boot media, and provision the NVMe root.
#
# TWO DEVICES
# -----------
#   1. microSD  -- the BOOT CHAIN only: bl2 / ubootenv / factory / fip /
#      production (the raw FIT).  This is forced by the hardware: the MT7988
#      BootROM loads BL2 from raw sector 34 of mmc 0, and BL2 then looks up the
#      GPT partition *named* `fip` on the same device.  Neither can move to
#      NVMe without reflashing SPI-NAND, which is never done.
#
#   2. NVMe     -- the ROOT filesystem (btrfs: /root, /nix, /persist).  This is
#      where space and throughput matter: the closure is ~7.3 GiB once the
#      QEMU VM is included, and a 30 GB SD card's writeback path throttles
#      builds into `wbt_wait` stalls.
#
# The kernel cmdline carries `root=fstab`, so stage-1 resolves the root from
# /etc/fstab -- whose entry is the PARTLABEL `nixos-root` on the NVMe.
#
# LAYOUT
#   SD   #  name        start(sec)  size         type
#        1  bl2               34    8158  (~4M)  Linux
#        2  ubootenv        8192    1024  (512K) Linux
#        3  factory         9216    4096  (2M)   Linux
#        4  fip            13312    8192  (4M)   EFI
#        5  production    327680  917504 (448M)  Linux   <- raw NixOS FIT
#   NVMe 1  nixos-root      2048   <fills>        Linux   <- btrfs
#
# USAGE
#   ./mk-sd-image.sh build [VENDOR_IMG]   # assemble the SD boot image
#   ./mk-sd-image.sh flash <sd-device>    # write the SD boot image
#   ./mk-sd-image.sh root <nvme-device>   # mkfs + lay down the btrfs root
#
# <nvme-device> is normally /dev/nvme0n1 (the Samsung 960 PRO).  DESTRUCTIVE.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo "$HERE/../../..")"
WORK=/tmp/bpi-r4/sdimg
IMG="$WORK/s-nodus-boot.img"

# SD geometry (512-byte sectors); must match disko.nix.
#
# The card carries BOTH the boot chain and a complete root filesystem.  That is
# deliberate: it makes the board boot a self-consistent system with no
# dependency on the NVMe, which is what allows the SSD to be installed and a
# failed NVMe install to be recovered from.
P1_S=34;       P1_N=8158               # bl2
P2_S=8192;     P2_N=1024               # ubootenv
P3_S=9216;     P3_N=4096               # factory
P4_S=13312;    P4_N=8192               # fip
P5_S=327680;   P5_N=917504             # production (raw FIT)
P6_S=1245184;  P6_GIB=8                # nixos-root (btrfs): rootfs + headroom
#
# The card does NOT hand 100% of its space to the root: the remainder stays
# unallocated so it can be grown later without reflashing.  Space is not the
# constraint it once was -- swap is a swapfile on the btrfs root (see the
# swapDevices comment in default.nix), not a partition, so there is no token
# swap partition to allocate and nothing that can crowd it out.
#
# The P6_GIB slack above the rootfs image exists for exactly that swapfile
# plus the working room an on-board rebuild needs.

# NVMe root geometry.
R_S=2048                               # 2048-aligned, 1 MiB in

DISK_GUID="5452574F-2211-4433-5566-778899AABB00"
U1="5452574F-2211-4433-5566-778899AABB01"
U2="5452574F-2211-4433-5566-778899AABB02"
U3="5452574F-2211-4433-5566-778899AABB03"
U4="5452574F-2211-4433-5566-778899AABB04"
U5="5452574F-2211-4433-5566-778899AABB05"
U6="5452574F-2211-4433-5566-778899AABB06"

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

# ---------------------------------------------------------------- build ----
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

  local fsz; fsz=$(stat -c%s "$FIT")
  if [ "$fsz" -gt $(( P5_N * 512 )) ]; then
    echo "!! FIT ($fsz B) exceeds production partition ($(( P5_N * 512 )) B)"; exit 1
  fi

  echo ">> building the SD root filesystem (btrfs image with the store closure)"
  local ROOTFS
  ROOTFS=$(nix build --print-out-paths --no-link \
    "$REPO#nixosConfigurations.s-nodus.config.system.build.rootfsImage")
  echo "   rootfs = $ROOTFS ($(du -h --apparent-size "$ROOTFS" | cut -f1) apparent)"

  # Size the root partition to the rootfs image, then add slack so the first
  # boot has room to write.  The image is sparse/compact: it is exactly as large
  # as its contents, so `du --apparent-size` (not st_size of the sparse file) is
  # what must fit.  Grow-to-fill happens on the running system.
  # Root is a FIXED size (P6_GIB), not sized to the rootfs image: the slack
  # holds the swapfile and gives an on-board rebuild somewhere to work.  The
  # image itself is compact, so `du --apparent-size` (not the sparse file's
  # st_size) is what has to fit.
  local rootBytes rootBlocks
  rootBytes=$(du -B 512 --apparent-size "$ROOTFS" | awk '{ print $1 }')
  local P6_N=$(( P6_GIB * 2097152 ))
  local needBlocks=$(( rootBytes + 65536 ))     # +32 MiB of slack
  if [ "$needBlocks" -gt "$P6_N" ]; then
    echo "!! rootfs ($(( needBlocks / 2048 / 1024 )) MiB) does not fit the ${P6_GIB} GiB root partition"
    exit 1
  fi
  local p6End=$(( P6_S + P6_N - 1 ))
  # The image covers the boot chain and the root; the rest of the card is left
  # unallocated so the running system can grow the root into it if needed.
  local total=$(( p6End + 34 ))
  echo ">> assembling $IMG (total=$total sec = $(( total/2/1024 )) MiB)"
  echo "   root ${P6_GIB} GiB | rest left unallocated"
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
  "$SGDISK" -a 1 -n 6:$P6_S:$p6End           -t 6:8300 -c 6:nixos-root -u 6:$U6 "$IMG" >/dev/null
  # Vendor GPT attribute flags (RequiredPartition / LegacyBIOSBootable).
  "$SGDISK" -A 1:set:0 -A 1:set:2 -A 2:set:0 -A 3:set:0 -A 4:set:0 "$IMG" >/dev/null

  echo ">> writing payloads"
  dd if="$FW/bl2.bin"  of="$IMG" bs=512 seek=$P1_S conv=notrunc status=none
  dd if="$FW/fip.bin"  of="$IMG" bs=512 seek=$P4_S conv=notrunc status=none
  dd if="$FIT"         of="$IMG" bs=512 seek=$P5_S conv=notrunc status=none

  # Partition 6 is left EMPTY here on purpose.  It is created now only so the
  # GPT geometry is final; its btrfs filesystem (with the /root, /nix and
  # /persist subvolumes the config's fileSystems declare) is written by the
  # `populate` command against the flashed device.
  echo ">> partition 6 left for 'populate' (btrfs with subvolumes)"
  # U-Boot environment: MANDATORY.  U-Boot's image_setup_libfdt() always
  # overwrites /chosen/bootargs with env_get("bootargs"), so the FIT's bootargs
  # are ignored and the vendor default (root=/dev/fit0) cannot boot NixOS.
  echo ">> writing U-Boot environment (ubootenv partition)"
  _write_uboot_env_in_image "$IMG"

  local got
  got=$(dd if="$IMG" bs=512 skip=$P4_S count=1 status=none | od -An -tx1 | tr -d ' \n')
  [ "${got:0:8}" = "010064aa" ] || { echo "!! FIP header not at fip start"; exit 1; }
  got=$(dd if="$IMG" bs=512 skip=$P5_S count=1 status=none | od -An -tx1 | tr -d ' \n')
  [ "${got:0:8}" = "d00dfeed" ] || { echo "!! FIT magic not at production start"; exit 1; }
  echo "   verified: fip header + production FIT magic"

  echo ">> built $IMG ($(du -h "$IMG" | cut -f1))"
  echo "   flash with:  $0 flash <sd-device>"
  echo "   then:        $0 populate <sd-device>   (writes the root filesystem)"
  echo "   the card then boots NixOS with no NVMe present."
  echo "   stage 2 (move the root to the NVMe) is run FROM the booted system."
}

# Write the U-Boot environment into the ubootenv partition (p2) of an image.
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
  local env="$WORK/uboot.env"

  # uboot-env.txt is used verbatim: its init= points at the stable
  # /nix/var/nix/profiles/system symlink, so it does not need to track the
  # current toplevel (and a rebuild that moves the profile is picked up on
  # the next boot without rewriting this env).
  #
  # mkenvimage writes ONE copy of the given size; write it twice ourselves.
  nix shell nixpkgs#ubootTools -c \
    mkenvimage -s 0x40000 -r -o "$env" "$HERE/uboot-env.txt"

  [ "$(stat -c%s "$env")" -eq 262144 ] || { echo "!! unexpected env size"; exit 1; }

  dd if="$env" of="$IMG" bs=4096 seek=$(( P2_S / 8 ))      conv=notrunc status=none
  dd if="$env" of="$IMG" bs=4096 seek=$(( P2_S / 8 + 64 )) conv=notrunc status=none

  local a b e
  e=$(sha256sum "$env" | cut -d' ' -f1)
  a=$(dd if="$IMG" bs=4096 skip=$(( P2_S / 8 ))      count=64 status=none | sha256sum | cut -d' ' -f1)
  b=$(dd if="$IMG" bs=4096 skip=$(( P2_S / 8 + 64 )) count=64 status=none | sha256sum | cut -d' ' -f1)
  [ "$a" = "$e" ] && [ "$b" = "$e" ] || { echo "!! ubootenv write mismatch"; exit 1; }
  echo "   env written (2 copies, sha $e)"
}

# ---------------------------------------------------------------- flash ----
flash() {
  local DEV="${1:?usage: $0 flash <sd-device>}"
  [ -b "$DEV" ] || { echo "!! $DEV is not a block device"; exit 1; }
  [ -s "$IMG" ] || { echo "!! image not built (run: $0 build)"; exit 1; }
  echo ">> FLASHING $IMG -> $DEV"
  sudo dd if="$IMG" of="$DEV" bs=4M conv=fsync status=progress
  sync
  sudo "$SGDISK" -e "$DEV" >/dev/null
  sudo partprobe "$DEV" 2>/dev/null || sudo blockdev --rereadpt "$DEV" 2>/dev/null || true
  echo ">> flashed. layout:"; sudo "$SGDISK" -p "$DEV" | sed -n '1,20p'
}

# ------------------------------------------------------------- nvme root ----
# Create the btrfs root on the NVMe with the subvolumes the system expects
# (/root, /nix, /persist) and lay down the store closure + toplevel.
#
# Partitioning is done by disko (diskoConfigurations.s-nodus-disk), so the
# on-disk layout cannot drift from disko.nix.
#
# ROOT_IMAGE may be passed to reuse an already-built rootfs image instead of
# building one here.  That matters: evaluating this configuration peaks around
# 3.3 GiB, which is close to the board's 4 GiB, so an on-board build is prone to
# the OOM killer.  Build it on a bigger machine and hand it over.
root() {
  local DEV="${1:?usage: $0 root <nvme-device> [rootfs-image]}"
  local ROOT_IMAGE="${2:-}"
  [ -b "$DEV" ] || { echo "!! $DEV is not a block device"; exit 1; }
  case "$DEV" in
    /dev/mmcblk*|/dev/mtd*) echo "!! $DEV is the boot device; the root goes on NVMe"; exit 1 ;;
  esac

  if [ -n "$ROOT_IMAGE" ]; then
    [ -e "$ROOT_IMAGE" ] || { echo "!! rootfs image not found: $ROOT_IMAGE"; exit 1; }
  else
    echo ">> building rootfs (flat btrfs image with the store closure)"
    echo "   NOTE: this evaluates the whole network pipeline; if the board OOMs,"
    echo "         build it elsewhere and pass the path as the second argument."
    ROOT_IMAGE=$(nix build --builders '' --print-out-paths --no-link \
      "$REPO#nixosConfigurations.s-nodus.config.system.build.rootfsImage")
  fi
  echo "   rootfs = $ROOT_IMAGE"

  # Partition with disko.  The `s-nodus-root` output describes ONLY the NVMe,
  # so this cannot touch the microSD's boot chain.
  echo ">> partitioning $DEV via disko (root-only: sdcard untouched)"
  sudo nix run "$REPO#diskoConfigurations.s-nodus-root" -- \
    --mode destroy,format,mount \
    --argstr rootDisk "$DEV" \
    "$REPO#s-nodus-root" || {
      echo "   !! disko failed; see above.  Not falling back to raw sgdisk --"
      echo "   !! a partial layout is worse than none."
      exit 1
    }

  local PART; PART=$(partition_of "$DEV" 1)
  echo ">> btrfs subvolumes + populate on $PART"
  _populate_btrfs_root "$PART" "$ROOT_IMAGE"

  echo ">> done. layout:"; sudo "$SGDISK" -p "$DEV" | sed -n '1,20p'
}

# Resolve partition N of a device (handles nvme0n1p1 vs sda1).
partition_of() {
  local dev="$1" idx="$2"
  case "$dev" in
    *[0-9]) echo "${dev}p${idx}" ;;
    *)      echo "${dev}${idx}" ;;
  esac
}

_populate_btrfs_root() {
  local PART="$1" ROOT="$2"
  local m=/tmp/bpi-r4/root-mnt src=/tmp/bpi-r4/root-src
  sudo umount -R "$m" 2>/dev/null || true
  sudo umount -R "$src" 2>/dev/null || true
  rm -rf "$m" "$src"; mkdir -p "$m" "$src"

  sudo mount -o ro,loop "$ROOT" "$src"

  sudo mkfs.btrfs -q -f -L nixos-root "$PART"
  sudo mount "$PART" "$m"
  sudo btrfs subvolume create "$m/root"    >/dev/null
  sudo btrfs subvolume create "$m/nix"     >/dev/null
  sudo btrfs subvolume create "$m/persist" >/dev/null
  # Dedicated subvolume for the swapfile.  It must exist so /persist/swap
  # mounts and swapon finds the file; it is also what keeps the swapfile out of
  # services.btrfs.autoScrub, which lists only /, /nix and /persist.  btrfs
  # checksums every data block and a live swapfile is rewritten continuously,
  # so scrubbing it would report permanent false corruption.
  sudo btrfs subvolume create "$m/swap"    >/dev/null
  sudo umount "$m"

  # /nix subvolume: the store closure (chown -R 0:0 -- the flat rootfs image is
  # built by the unprivileged nix build user, and a non-root-owned store breaks
  # logrotate, systemd-tmpfiles and sudo).
  sudo mount -o subvol=/nix "$PART" "$m"
  sudo mkdir -p "$m/store"
  sudo cp -a "$src/nix/store/." "$m/store/"
  sudo chown -R 0:0 "$m/store"
  sudo chmod 1775 "$m/store"
  sudo umount "$m"

  # /root subvolume: everything else the image carries + an empty /nix mountpoint.
  sudo mount -o subvol=/root "$PART" "$m"
  sudo mkdir -p "$m/nix"
  for f in "$src"/*; do
    case "$(basename "$f")" in
      nix) : ;;
      *) sudo cp -a "$f" "$m/" ;;
    esac
  done

  # Point /nix/var/nix/profiles/system at the toplevel the boot chain expects.
  #
  # This is MANDATORY and was previously missing: the kernel cmdline is
  # `init=/nix/var/nix/profiles/system/init`, and stage 1 resolves that symlink
  # *inside the new root*.  Without it (or pointing at a toplevel the store does
  # not contain) the boot fails at "Find NixOS closure" even though the root is
  # mounted correctly.
  #
  # The toplevel is taken from the image's own store rather than passed in, so
  # the link can only ever name a path that is actually present -- a manually
  # written link to a stale toplevel is exactly how this broke before.
  local toplevel
  toplevel=$(find "$src/nix/store" -maxdepth 1 -name '*-nixos-system-*' -printf '%f\n' 2>/dev/null | sort | tail -1)
  [ -n "$toplevel" ] || { echo "!! no nixos-system toplevel in the rootfs image"; exit 1; }
  echo ">> system profile -> /nix/store/$toplevel"
  sudo mkdir -p "$m/nix/var/nix/profiles"
  sudo ln -sfn "/nix/store/$toplevel" "$m/nix/var/nix/profiles/system"

  # Verify it resolves *within the store we are about to write*, not merely
  # that the link exists -- the target is what stage 1 execs.
  [ -x "$src/nix/store/$toplevel/init" ] \
    || { echo "!! $toplevel has no /init; image is incomplete"; exit 1; }
  [ -e "$src/nix/store/$toplevel/etc/fstab" ] \
    || { echo "!! $toplevel has no /etc/fstab"; exit 1; }
  echo "   verified: system -> $toplevel (init + etc/fstab present)"

  sudo chown -R 0:0 "$m"
  sudo umount "$m"
  sudo umount "$src"

  rm -rf "$m" "$src" 2>/dev/null || true
}

# ---------------------------------------------------------- scratch swap -#
# Throwaway swap on a disk that is NOT part of the machine's layout.
#
# The board has 4 GiB of RAM and evaluating this configuration peaks near
# 3.3 GiB, so an on-board install can trip the OOM killer.  Enabling swap on a
# spare NVMe for the duration of the install makes that survivable.  This is
# deliberately a one-shot command rather than declarative config: the disk
# holds nothing the running system depends on, and is expected to be reused
# (or removed) afterwards.
scratch_swap() {
  local DEV="${1:?usage: $0 swap <scratch-disk>}"
  [ -b "$DEV" ] || { echo "!! $DEV is not a block device"; exit 1; }
  case "$DEV" in
    /dev/mmcblk*|/dev/mtd*) echo "!! refusing to use the boot device as scratch swap"; exit 1 ;;
    /dev/nvme0n1)          echo "!! $DEV is the root disk; pass the OTHER nvme"; exit 1 ;;
  esac

  echo ">> creating throwaway swap on $DEV"
  sudo wipefs -a "$DEV" >/dev/null 2>&1 || true
  # sfdisk is in util-linux and always present; sgdisk is not.
  printf 'label: gpt\nstart=2048, type=0657FD6D-A4AB-43C4-84E5-0933C84B4F4F, name=swap\n' \
    | sudo sfdisk "$DEV" >/dev/null
  sudo partprobe "$DEV" 2>/dev/null || sudo blockdev --rereadpt "$DEV" 2>/dev/null || true
  sleep 2
  sudo mkswap -L scratch-swap "$(partition_of "$DEV" 1)" >/dev/null
  sudo swapon "$(partition_of "$DEV" 1)"
  swapon --show
  free -h | head -2
  echo ">> NOTE: not persisted.  This disk is not in disko.nix by design."
}

# ------------------------------------------------------------- populate ----
# Write the stage-1 root filesystem into partition 6 of a flashed SD card.
#
# Separate from `build` because the two media disagree on what a root is:
# `make-btrfs-fs` produces a FLAT image (store + files, no subvolumes), while
# this system's fileSystems declare `subvol=/root`, `/nix` and `/persist`.  dd'ing
# the flat image in leaves a root that cannot satisfy them -- the kernel asks for
# subvol=/root and finds nothing.
#
# So the partition is formatted here and populated by _populate_btrfs_root, the
# same helper `root` uses for the NVMe.
populate() {
  local DEV="${1:?usage: $0 populate <sd-device> [rootfs-image]}"
  local ROOT_IMAGE="${2:-}"
  [ -b "$DEV" ] || { echo "!! $DEV is not a block device"; exit 1; }
  case "$DEV" in
    /dev/mmcblk*|/dev/mtd*) : ;;
  esac

  if [ -z "$ROOT_IMAGE" ]; then
    echo ">> building the root filesystem image"
    ROOT_IMAGE=$(nix build --print-out-paths --no-link \
      "$REPO#nixosConfigurations.s-nodus.config.system.build.rootfsImage")
  fi
  echo "   rootfs = $ROOT_IMAGE"

  local PART; PART=$(partition_of "$DEV" 6)
  echo ">> formatting $PART (btrfs, label nixos-root)"
  sudo umount "$PART" 2>/dev/null || true
  sudo wipefs -a "$PART" >/dev/null 2>&1 || true

  echo ">> subvolumes + populate on $PART"
  _populate_btrfs_root "$PART" "$ROOT_IMAGE"
  echo ">> done.  partition 6 is ready."
}

cmd="${1:-}"; shift || true
case "$cmd" in
  build) build "$@" ;;
  flash) flash "$@" ;;
  populate) populate "$@" ;;
  root)  root "$@" ;;
  swap)  scratch_swap "$@" ;;
  *) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
