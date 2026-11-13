#!/usr/bin/env bash
# Build and flash the s-nodus boot media, and provision the NVMe root.
#
# TWO DEVICES
# -----------
#   1. microSD  -- the BOOT CHAIN only: bl2 / ubootenv / factory / fip / ESP.
#      This is forced by the hardware: the MT7988 BootROM loads BL2 from raw
#      sector 34 of mmc 0, and BL2 then looks up the GPT partition *named*
#      `fip` on the same device.  Neither can move to NVMe without reflashing
#      SPI-NAND, which is never done.
#
#      BL2 and the FIP are built from source by nixos-hardware's
#      bananapi/bpi-r4-pro atf.nix/fip.nix -- no vendor firmware image is
#      needed.  U-Boot (inside the FIP) has CONFIG_EFI_LOADER, so it boots
#      EFI/BOOT/BOOTAA64.EFI from the ESP, and systemd-boot takes over.
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
#        5  ESP           102400  524288 (256M)  EFI   <- BOOTAA64.EFI + entries
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

# Optional local nixos-hardware checkout to build the board firmware from
# (BL2/BL31/U-Boot).  Unset, the flake's pinned nixos-hardware input is used.
#
#   NIXOS_HARDWARE=/path/to/nixos-hardware ./mk-sd-image.sh build
#
# This exists so a change to the board support can be tested on a real card
# before it is pinned, instead of building a board that differs from the source
# being edited.
NH_ARGS=()
if [ -n "${NIXOS_HARDWARE:-}" ]; then
  [ -f "$NIXOS_HARDWARE/flake.nix" ] || { echo "!! NIXOS_HARDWARE=$NIXOS_HARDWARE is not a flake"; exit 1; }
  NH_ARGS=(--override-input "nixos-hardware" "path:$NIXOS_HARDWARE")
  echo ">> using nixos-hardware from $NIXOS_HARDWARE"
fi

# Every `nix build` in this script goes through nix_build, which applies the
# NIXOS_HARDWARE override once so every artifact (BL2, FIP, rootfs, the ESP
# builder, the toplevel) is taken from the same nixos-hardware revision.  A
# mixed build would let the firmware and the system disagree, which on this
# board means an unbootable card.
#
# Build speed is handled in nix_build below: on an x86_64 build machine it
# cross-builds instead of running aarch64 builders under qemu-aarch64.
nix_build() {
  local attr="$1"
  local override=()
  # Extra nix flags; unset by default.
  local extra=()
  # S_NODUS_LOCAL_ONLY pins the build to THIS machine (benchmarking a host, or
  # when the configured remote builders are busy/unreachable).
  #
  # `builders` is a SETTING, not a `nix build` flag: `--builders=` is rejected
  # as an unrecognised flag, and a bare `--builders ""` splits into an option
  # whose value becomes the next argv entry (observed: it kept offloading to
  # s-sigma instead of failing).
  if [ -n "${S_NODUS_LOCAL_ONLY:-}" ]; then
    # No remote builders, and accept aarch64 OUTPUTS on this machine.
    #
    # A cross build produces derivations whose `system` is aarch64-linux; nix
    # refuses those with
    #   Reason: platform mismatch
    #   Required system: 'aarch64-linux'
    #   Current system: 'x86_64-linux'
    # unless the host advertises the platform.  The builders in this fleet have
    # `extra-platforms = aarch64-linux` in /etc/nix/nix.conf; a plain laptop
    # does not, and /etc/nix/nix.conf is read-only there, so pass it here.
    extra=(--option builders "" --option extra-platforms "aarch64-linux")
  fi
  if [ -n "${NIX_BUILD_ARGS:-}" ]; then
    # Split on spaces into separate argv entries.
    #
    # To pin the build to THIS machine, pass
    #     NIX_BUILD_ARGS="--option builders ''"
    # (`--builders` is a SETTING, not a `nix build` flag: `--builders=` is
    # rejected as an unrecognised flag, and a bare `--builders ""` splits into
    # an option whose value becomes the next argument. Both were observed to
    # either fail or silently keep offloading to s-sigma.)
    # shellcheck disable=SC2206
    extra=($NIX_BUILD_ARGS)
  fi
  if [ -n "${NIXOS_HARDWARE:-}" ]; then
    override=(--override-input "nixos-hardware" "path:$NIXOS_HARDWARE")
  fi

  # Cross-build on a non-aarch64 machine.
  #
  # nixpkgs.buildPlatform defaults to aarch64-linux for this host, so a plain
  # `nix build .#...` produces derivations whose builders are aarch64 binaries.
  # On an x86_64 build machine every one of those runs through binfmt_misc
  # qemu-aarch64, which is 10-50x slower: the ~7 GiB closure (kernel + the QEMU
  # cobalt VMs) did not finish in hours.
  #
  # extendModules adds the platform override to the FLAKE's configuration, so
  # nixpkgs selects its x86_64 -> aarch64 cross toolchain and aarch64 objects
  # are compiled by the NATIVE compiler.  The resulting image is identical; only
  # the build machine's work changes.
  #
  # S_NODUS_NO_CROSS=1 forces the native (emulated) path, which is what a
  # rebuild ON the board (an aarch64 host) uses anyway.
  if [ -z "${S_NODUS_NO_CROSS:-}" ] && [ "$(uname -m)" != "aarch64" ]; then
    nix build "${override[@]}" "${extra[@]}" --impure --print-out-paths --no-link --expr "
      let
        f = builtins.getFlake \"$REPO\";
        cfg = f.nixosConfigurations.s-nodus.extendModules {
          modules = [ { nixpkgs.buildPlatform = \"$(uname -m)-linux\"; } ];
        };
      in
      cfg.config.$attr" \
      || return 1
  else
    nix build "${override[@]}" "${extra[@]}" \
      "$REPO#nixosConfigurations.s-nodus.config.$attr" --print-out-paths --no-link
  fi
}

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
# ESP: systemd-boot + the kernels/initrds for every retained generation.
# 256 MiB holds BOOTAA64.EFI (a few hundred KiB) plus ~20 kernel+initrd pairs.
# ESP: FAT32 holding BOOTAA64.EFI plus a kernel+initrd PER RETAINED GENERATION.
# One generation is ~70 MiB (kernel ~12 MiB + initrd ~55 MiB), and
# systemd-boot.configurationLimit keeps 20, so 256 MiB overflowed on the second
# generation with ENOSPC. 1 GiB leaves room for ~14, and the ESP is cheap next
# to the root.
P5_S=102400;   P5_N=2097152            # ESP (FAT32), 1 GiB
# Root starts after the ESP. 102400 + 2097152 = 2199552 sectors, rounded up to
# the next 2048 boundary.  Keeping this derived from P5 avoids the silent
# overlap that a hand-maintained constant would reintroduce when the ESP grows.
P6_S=$(( ((P5_S + P5_N) + 2047) / 2048 * 2048 ))
P6_GIB=24                               # nixos-root (btrfs): rootfs + headroom
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
  # No vendor image is needed: BL2, BL31 and U-Boot are all built from source by
  # nixos-hardware's bananapi/bpi-r4-pro (atf.nix, uboot.nix, fip.nix).  The
  # argument is still accepted so existing invocations keep working.
  mkdir -p "$WORK"

  echo ">> building the board firmware from source (BL2 + FIP)"
  local BL2 FIP
  BL2=$(nix_build "system.build.bpiR4ProBl2")
  FIP=$(nix_build "system.build.bpiR4ProFip")
  echo "   bl2 = $BL2 ($(stat -c%s "$BL2") bytes)"
  echo "   fip = $FIP ($(stat -c%s "$FIP") bytes)"

  local bsz; bsz=$(stat -c%s "$BL2")
  [ "$bsz" -le $(( P1_N * 512 )) ] \
    || { echo "!! BL2 ($bsz B) exceeds its ${P1_N}-sector slot ($(( P1_N * 512 )) B)"; exit 1; }
  local fsz; fsz=$(stat -c%s "$FIP")
  [ "$fsz" -le $(( P4_N * 512 )) ] \
    || { echo "!! FIP ($fsz B) exceeds the fip partition ($(( P4_N * 512 )) B)"; exit 1; }

  echo ">> building the SD root filesystem (btrfs image with the store closure)"
  local ROOTFS
  ROOTFS=$(nix_build "system.build.rootfsImage")
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
  "$SGDISK" -a 1 -n 5:$P5_S:$(( P5_S+P5_N-1 )) -t 5:ef00 -c 5:ESP        -u 5:$U5 "$IMG" >/dev/null
  "$SGDISK" -a 1 -n 6:$P6_S:$p6End           -t 6:8300 -c 6:nixos-root -u 6:$U6 "$IMG" >/dev/null
  # Vendor GPT attribute flags (RequiredPartition / LegacyBIOSBootable).
  "$SGDISK" -A 1:set:0 -A 1:set:2 -A 2:set:0 -A 3:set:0 -A 4:set:0 "$IMG" >/dev/null

  echo ">> writing payloads"
  dd if="$BL2"        of="$IMG" bs=512 seek=$P1_S conv=notrunc status=none
  dd if="$FIP"        of="$IMG" bs=512 seek=$P4_S conv=notrunc status=none

  # Partition 5 is the ESP.  `_populate_esp` builds it on a throwaway
  # one-partition GPT (bootctl refuses an unpartitioned loop device), then
  # extracts just that partition to $WORK/esp-part.img.  The card P5 must hold
  # the FAT filesystem DIRECTLY -- writing the throwaway image instead would
  # nest a second GPT inside P5, which nothing can mount.
  echo ">> formatting + populating ESP (partition 5)"
  local esp="$WORK/esp.img"
  local espPart="$WORK/esp-part.img"
  rm -f "$esp" "$espPart"
  truncate -s $(( P5_N * 512 )) "$esp"
  _populate_esp "$esp"
  [ -f "$espPart" ] || { echo "!! ESP partition was not extracted" >&2; exit 1; }
  dd if="$espPart" of="$IMG" bs=512 seek=$P5_S conv=notrunc status=none

  # Partition 6 is left EMPTY here on purpose.  It is created now only so the
  # GPT geometry is final; its btrfs filesystem (with the /root, /nix and
  # /persist subvolumes the config's fileSystems declare) is written by the
  # `populate` command against the flashed device.
  echo ">> partition 6 left for 'populate' (btrfs with subvolumes)"
  # U-Boot environment.  It no longer carries the real bootargs (systemd-boot
  # writes the per-generation command line into the ESP); it provides
  # `bootcmd=bootflow scan -lb` plus a fallback cmdline for a manual boot from
  # the U-Boot console.
  echo ">> writing U-Boot environment (ubootenv partition)"
  _write_uboot_env_in_image "$IMG"

  local got
  got=$(dd if="$IMG" bs=512 skip=$P1_S count=1 status=none | head -c 11)
  [ "$got" = "SDMMC_BOOT" ] || { echo "!! BL2 magic not at sector $P1_S (got '$got')"; exit 1; }
  got=$(dd if="$IMG" bs=512 skip=$P4_S count=1 status=none | od -An -tx1 | tr -d ' \n')
  [ "${got:0:8}" = "010064aa" ] || { echo "!! FIP header not at fip start"; exit 1; }
  echo "   verified: BL2 magic at sector $P1_S + FIP header at sector $P4_S"

  echo ">> built $IMG ($(du -h "$IMG" | cut -f1))"
  echo "   flash with:  $0 flash <sd-device>"
  echo "   then:        $0 populate <sd-device>   (writes the root filesystem)"
  echo "   the card then boots NixOS with no NVMe present."
  echo "   stage 2 (move the root to the NVMe) is run FROM the booted system."
}

# Populate the ESP (a FAT image file) with systemd-boot and the current
# generation's boot entry.
#
# This runs NixOS's own systemd-boot builder against the mounted ESP rather than
# copying BOOTAA64.EFI and writing loader entries by hand: the builder knows the
# EFI architecture, the entry format, and how `bootctl install` lays out
# /EFI/BOOT and /EFI/systemd.  Reimplementing that is how these images end up
# subtly unbootable.
#
# NIXOS_INSTALL_BOOTLOADER=1 makes it perform a full `bootctl install` (writing
# the removable-media fallback BOOTAA64.EFI) instead of only refreshing the
# existing installation, which is what a fresh image needs.
_populate_esp() {
  local ESPIMG="$1"

  # `system.build.installBootLoader` is the generated SCRIPT itself (a single
  # file named install-systemd-boot.sh), not a package with bin/.  Calling
  # "$BUILDER/bin/install-systemd-boot" fails with "Not a directory".
  local BUILDER
  BUILDER=$(nix_build "system.build.installBootLoader") \
    || { echo "!! could not build installBootLoader"; exit 1; }
  [ -f "$BUILDER" ] || { echo "!! installBootLoader is not a file: $BUILDER" >&2; exit 1; }

  local TOPLEVEL
  TOPLEVEL=$(nix_build "system.build.toplevel")

  # `bootctl install` refuses a loop device that is not a PARTITIONED block
  # device ("File system /dev/loop1 is not located on a partitioned block
  # device").  So give the ESP image a GPT with one ESP partition and attach it
  # with `losetup -P`, which creates /dev/loopNp1.  `bootctl` then installs into
  # that partition and writes the removable-media EFI/BOOT/BOOTAA64.EFI.
  #
  # The builder has its mount point COMPILED IN (efiSysMountPoint, /boot), and
  # bootctl offers no flag we control from here, so the ESP partition is mounted
  # over /boot inside a private mount namespace: the builder writes into the
  # image and the build machine's real /boot is never touched.  (A plain
  # `mount ... $mnt` is not enough -- the builder ignores $mnt and was observed
  # writing loader/random-seed into the build machine's real /boot.)
  #
  # The aarch64 bootctl runs through binfmt_misc/qemu-user, which is fine: it is
  # one small tool, not the build.
  sudo unshare -m --propagation private bash -eu -c '
    img="$1"; builder="$2"; toplevel="$3"; tool="$4"
    loopdev=""
    cleanup() {
      umount /boot 2>/dev/null || true
      [ -n "$loopdev" ] && losetup -d "$loopdev" 2>/dev/null || true
    }
    trap cleanup EXIT

    # A single ESP partition filling the image.
    "$tool" -Z "$img" >/dev/null 2>&1 || true
    "$tool" -n 1:2048:0 -t 1:ef00 -c 1:ESP "$img" >/dev/null

    loopdev=$(losetup -fP --show "$img")
    part="${loopdev}p1"
    [ -b "$part" ] || { echo "!! no partition device for $loopdev" >&2; exit 1; }

    # The filesystem goes on the PARTITION, not on the bare image: bootctl
    # refuses a loop device that is not itself partitioned.
    mkfs.vfat -F 32 -n ESP "$part" >/dev/null

    mount -t tmpfs tmpfs /boot
    mount "$part" /boot
    NIXOS_INSTALL_BOOTLOADER=1 bash "$builder" "$toplevel"

    # Verify INSIDE the namespace, against the mounted partition.  Checking the
    # outer ESPIMG with `mdir -i` cannot work: the filesystem now lives on the
    # partition, not at offset 0 of the image, so mdir sees the GPT instead.
    # U-Boot only looks for the removable-media fallback path, so a missing
    # EFI/BOOT/BOOTAA64.EFI is an unbootable card.
    test -f /boot/EFI/BOOT/BOOTAA64.EFI || {
      echo "!! ESP is missing EFI/BOOT/BOOTAA64.EFI" >&2
      find /boot -maxdepth 3 >&2 || true
      exit 1
    }
    echo "   ESP contains EFI/BOOT/BOOTAA64.EFI"

    umount /boot
    # Copy just the PARTITION out to $5.  The image file carries a throwaway GPT
    # only so bootctl accepts the loop device; the card P5 must hold the FAT
    # filesystem directly, otherwise the ESP ends up two levels deep (card GPT
    # -> P5 -> nested GPT -> FAT) which nothing can mount.
    dd if="$part" of="$5" bs=8M status=none
    losetup -d "$loopdev"; loopdev=""
  ' _ "$ESPIMG" "$BUILDER" "$TOPLEVEL" "$SGDISK" "$WORK/esp-part.img"
}

# Write the U-Boot environment into the ubootenv partition (p2) of an image.
#
# This environment is now small: U-Boot's CONFIG_BOOTCOMMAND already scans for
# the ESP (`bootflow scan -lb`), and each systemd-boot entry carries its own
# kernel command line.  What remains here is the fallback: a `bootargs` that can
# boot the system by hand from the U-Boot console if the ESP is damaged.
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
  echo ">> FLASHING boot chain of $IMG -> $DEV"

  # Copy only the ranges the BOOT CHAIN actually reads, not the whole image.
  #
  # The image is ~25 GiB because it declares a 24 GiB `nixos-root`, but the root
  # lives on the NVMe -- on the card that partition is empty padding.  dd'ing it
  # took tens of minutes over USB writeback throttling (measured 6-7 MiB/s,
  # wedged in rq_qos_wait, unkillable), for bytes nothing ever reads.
  #
  # What U-Boot/BL2/systemd actually touch:
  #   sector 34     bl2        (BootROM reads this address directly)
  #   sector 8192   ubootenv   (U-Boot environment)
  #   sector 13312  fip        (BL31 + U-Boot, the GPT entry named "fip")
  #   sector P5_S   ESP        (BOOTAA64.EFI + kernel/initrd per generation)
  # `factory` (3) and `nixos-root` (6) are skipped: neither is read to boot.
  # dd_range <label> <start-sector> <count-sectors>
  # 512-byte units throughout: every partition start here is 512-byte aligned
  # (the firmware offsets are raw sectors), so this needs no MiB rounding.
  dd_range() {
    local label="$1" start="$2" count="$3"
    echo "   $label: sectors $start..$(( start + count - 1 )) ($(( count * 512 / 1024 / 1024 )) MiB)"
    sudo dd if="$IMG" of="$DEV" bs=512 skip="$start" count="$count" \
      conv=fsync status=progress || { echo "!! dd failed for $label" >&2; exit 1; }
  }

  # Primary GPT (LBA 0..33) -- BL2 finds the `fip` partition BY NAME, so the
  # table must exist before anything else.  The backup table at the end of the
  # device is not written: it is regenerated by the sgdisk call below.
  sudo dd if="$IMG" of="$DEV" bs=512 count=$(( P1_S )) conv=fsync status=none
  dd_range bl2       "$P1_S" "$P1_N"
  dd_range ubootenv  "$P2_S" "$P2_N"
  # factory (P3) is deliberately skipped: nothing reads it.
  dd_range fip       "$P4_S" "$P4_N"
  dd_range ESP       "$P5_S" "$P5_N"
  # nixos-root (P6) is deliberately skipped: the root lives on the NVMe.
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
    ROOT_IMAGE=$(nix_build "system.build.rootfsImage")
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
  #
  # The system profile link is written HERE, not on /root.  The cmdline is
  # `init=/nix/var/nix/profiles/system/init`, and at runtime /nix is mounted from
  # THIS subvolume, which covers /root's own nix/ directory -- a link written on
  # /root is therefore invisible to stage 1, and the boot dies at "Find NixOS
  # closure" with the root mounted and looking healthy.
  #
  # The toplevel is read out of the image's own store rather than passed in, so
  # the link can only ever name a path that is actually present.
  sudo mount -o subvol=/nix "$PART" "$m"
  sudo mkdir -p "$m/store"
  sudo cp -a "$src/nix/store/." "$m/store/"
  sudo chown -R 0:0 "$m/store"
  sudo chmod 1775 "$m/store"

  local toplevel
  toplevel=$(find "$src/nix/store" -maxdepth 1 -name '*-nixos-system-*' -printf '%f\n' 2>/dev/null | sort | tail -1)
  [ -n "$toplevel" ] || { echo "!! no nixos-system toplevel in the rootfs image"; exit 1; }
  echo ">> system profile -> /nix/store/$toplevel (on the /nix subvolume)"
  sudo mkdir -p "$m/var/nix/profiles"
  sudo ln -sfn "/nix/store/$toplevel" "$m/var/nix/profiles/system"

  # Verify the target really is in the store we just wrote -- the link existing
  # is not enough, the toplevel is what stage 1 execs.
  [ -x "$m/store/$toplevel/init" ] \
    || { echo "!! $toplevel has no /init; image is incomplete"; exit 1; }
  echo "   verified: system -> $toplevel (init present)"
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
    ROOT_IMAGE=$(nix_build "system.build.rootfsImage")
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
