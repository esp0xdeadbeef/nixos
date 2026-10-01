# s-nodus — Banana Pi BPI-R4 Pro 4E

NixOS on a MediaTek MT7988A (Filogic 880) router board, booting from **microSD**.

At this stage s-nodus is deliberately minimal:

- **every Ethernet port is a plain DHCP client** (no routing, no NAT, no firewall);
- **serial console** on `ttyS0` is the primary access path;
- board support is **mainline** (kernel ≥ 6.19); no vendored/decompiled DTB.

The MaxLinear 10G switch, AS21010 10G PHYs, SFP+ muxes and Wi-Fi 7 (MT7996)
are **not** mainline yet and stay dark. They are intentionally out of scope.
For those later, see the reference port `ly4096x/BananaPi-R4-Pro-8X-OS`.

## Quick start (build + flash a card)

One command, from a machine with this repo and the vendor OpenWrt SD image
somewhere under `~/Downloads`:

```bash
sudo nixos/server/s-nodus/flash-s-nodus.sh /dev/sda
```

That builds the FIT + btrfs root, assembles the full GPT image (firmware blobs
included) and writes it to the card. Then cold-power-cycle the board.

## Boot chain

The board's **stock OpenWrt U-Boot is never reflashed**. It boots a FIT image
that NixOS provides. The exact contract, read verbatim out of the vendor FIP
blob, is:

```
cold power-on
  -> MTK BootROM
  -> BL2            (loaded from raw SD sector 34)
  -> BL2 reads the GPT and loads the ARM-TF FIP from the partition NAMED "fip"
       (if absent: "Partition 'fip' not found" -> "System halt!")
  -> BL31 + BL33/U-Boot
  -> bootcmd        = if pstore check ; then run boot_recovery ; else run boot_sdmmc ; fi
     boot_sdmmc     = run boot_production ; run boot_recovery
     boot_production = ... sdmmc_read_production && bootm $loadaddr#$bootconf#$bootconf_sd#$bootconf_extra
     sdmmc_read_production = part start mmc 0 production part_addr && \
                             part size  mmc 0 production part_size && run mmc_read_vol
     mmc_read_vol   = mmc read $loadaddr $part_addr 0x100 && imszb ... && \
                      test image_size -le part_size && mmc read ...
     loadaddr       = 0x50000000
     bootconf       = config-mt7988a-bananapi-bpi-r4-pro-4e
     bootconf_sd    = mt7988a-bananapi-bpi-r4-pro-4e-sd
     bootconf_extra = mt7988a-bananapi-bpi-r4-pro-4e-iphy
  -> NixOS (console ttyS0)
```

Two consequences drive everything below:

1. **The FIT must live raw at offset 0 of the GPT partition named
   `production`.** `./fit.nix` builds it; `mk-sd-image.sh` writes it.
2. **The `fip` partition must exist** (BL2 looks it up by name) and contain the
   vendor ARM-TF FIP, which cannot be built from source.

There is **no EFI/systemd-boot** on this board: the vendor U-Boot's built-in
env has no `bootefi`/`BOOTAA64.EFI` path. NixOS generation management is via
the btrfs root (subvol + store paths) and the FIT.

## Storage (`disko.nix`)

microSD only, GPT. The layout **replicates the vendor GPT geometry** because
the BootROM/BL2/U-Boot locate payloads by fixed sector + GPT name:

| # | Name | Start (sec) | Size | FS | Contents |
|---|---|---|---|---|---|
| 1 | `bl2` | 34 | 4 MiB | — | MTK BL2 |
| 2 | `ubootenv` | 8192 | 512 KiB | — | (zeros; U-Boot built-in env) |
| 3 | `factory` | 9216 | 2 MiB | — | (zeros) |
| 4 | `fip` | 13312 | 4 MiB | — | ARM-TF FIP (BL31 + BL33/U-Boot) |
| 5 | `production` | 327680 | 448 MiB | — | raw NixOS FIT |
| 6 | `nixos-root` | 1245184 | 100% | btrfs (`/root`,`/nix`,`/persist`) | `/` |

`bl2`/`fip` are signed vendor blobs; `production` holds the FIT. The `nixos-root`
btrfs label/PARTLABEL is what the FIT's bootargs resolve.

### Safety — write ONLY the microSD

- disko writes only the block device passed as `disk`;
- an **assertion refuses** obvious SPI-NAND targets (`/dev/mtd*`, `/dev/mtdblock*`);
- SD and eMMC share **one mmc controller** on MT7988, so names *can* flip —
  always pass a stable path (e.g. `/dev/disk/by-id/mmc-...`), never assume
  `/dev/sda`.

## Firmware blobs (`firmware.nix`)
BL2 and the ARM-TF FIP are signed vendor firmware and **cannot be built from
source**. `firmware.nix` slices them out of the vendor OpenWrt SD image:

- `bl2` → sectors 34..8191
- `fip` → sectors 13312..21503

The vendor image's `ubootenv`/`factory` partitions are all-zero in the shipped
image, so nothing is taken from them.

The blobs are a **fixed-output derivation** (content-pinned), so a changed or
corrupt vendor image fails the build instead of silently producing a card that
halts in firmware. To refresh after a vendor bump, update `outputHash` in
`firmware.nix` from the build's hash-mismatch error.

Because Banana Pi's download URLs are unstable and the image is not
redistributable, the vendor `.img` is passed in explicitly (`vendorImagePath`,
or `vendorImageUrl` + `vendorImageHash`). `mk-sd-image.sh build` finds the
newest `*BPI-R4Pro*sdcard*.img` under `~/Downloads` by default.

## Building the image

```bash
# assemble only (no card needed)
nixos/server/s-nodus/mk-sd-image.sh build [VENDOR_IMG]

# write it to a card and grow nixos-root to fill the card
nixos/server/s-nodus/mk-sd-image.sh flash /dev/sdX
```

The image is *compact* — `nixos-root` is only as large as its contents — and
`flash` grows the GPT partition and `btrfs resize max`es it afterwards.

## Why not plain `disko`

`disko` can express the GPT (this repo exposes `.#s-nodus-disk`), but it cannot
produce a bootable card on its own: it cannot write the raw BL2/FIP blobs, it
cannot write the U-Boot env, and disko has no "raw content in a partition"
type. `mk-sd-image.sh` therefore does the assembly.

## Two gotchas that cost real debugging time

### 1. U-Boot ignores the FIT's `/chosen/bootargs`

`image_setup_libfdt()` in U-Boot *always* overwrites `/chosen/bootargs` with
`env_get("bootargs")` (`board_fdt_chosen_bootargs()` returns `env_get("bootargs")`).
The vendor built-in default is

```
bootargs=console=ttyS0,115200n1 pci=pcie_bus_perf root=/dev/fit0 rootwait
```

and `root=/dev/fit0` is OpenWrt's device. So the real cmdline **must** live in
the U-Boot environment (`./uboot-env.txt`, written into the `ubootenv`
partition). Because writing an env replaces the built-in one entirely, that file
reproduces every variable the SD boot path needs.

### 2. `init=` is mandatory

NixOS's systemd initrd finds the system closure **only** from the `init=`
kernel parameter: `initrd-find-nixos-closure.service` scans `/proc/cmdline` for
`init=`, resolves it inside `/sysroot`, takes the dirname as the closure and
execs its `prepare-root`. Without it the boot dies immediately after
`Run /init as init process` with *"No init= parameter on the kernel command
line"*. Hence the full `init=/nix/store/<toplevel>/init` in `bootargs`.

### Root filesystem layout

The system's `fileSystems` (./disko.nix) are `/` -> `subvol=/root`,
`/nix` -> `subvol=/nix`, `/persist` -> `subvol=/persist`. The `sdImage` rootfs
image is FLAT (no subvolumes) and built by the unprivileged build user, so
`mk-sd-image.sh` creates the card's filesystem itself: `mkfs.btrfs`, the three
subvolumes, the closure into `/nix`, and `chown -R 0:0` (a store that is not
root-owned breaks logrotate's owner check and systemd-tmpfiles' "unsafe path
transition" guard).

## TODOs / hardening

- [ ] Replace `initialPassword` with a proper credential (sops/keys).
- [ ] Add a `recovery` partition + second FIT so the stock U-Boot's
      `boot_recovery` path works.
- [ ] 10G switch / SFP+ / Wi-Fi via an OpenWrt-delta kernel (see ly4096x port).
