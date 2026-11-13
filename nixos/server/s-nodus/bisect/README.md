# s-nodus BL2/FIP bisect

The board reset-loops with the firmware built by `bananapi/bpi-r4-pro`. On the
serial console:

    reboot: Power down
    PANIC at PC : 0x00000000430047ec
    F0: 102B 0000 ... T0: 0000 01B5 [0101]
    Jump to BL        (repeats)

and critically:

    grep -icE "U-Boot 2026|BL31|NOTICE" over the whole console == 0

No BL31 banner and no U-Boot banner, so the BootROM loads our BL2, BL2 jumps to
BL, and the SoC resets. The failure is the BL2 -> BL31 handoff, before U-Boot
is ever reached. The card contents themselves are fine (BL2 magic at sector 34,
FIP magic at 13312, EFI/BOOT/BOOTAA64.EFI and matching loader entries present),
so this is about the firmware, not the image layout.

## What the two FIPs look like

    OUR:    BL31 offset=0x90 size=0xA129 | BL33 offset=0xA1C0 size=0x1201C8
    VENDOR: BL31 offset=0x88 size=0xA129 | BL33 offset=0xA1B1 size=0x10E8C8

Same BL31 size in both; only BL33 (U-Boot) and alignment differ. The BL2
boot-ROM headers are byte-identical (`SDMMC_BOOT`, flags 0x00020000), with
different payloads.

## Test matrix

`./apply-variant.sh <letter> [device]` writes BL2 to sector 34 and the FIP to
sector 13312 (default `/dev/sda`). Neither the `factory` partition (9216) nor
the ESP is touched.

| variant | BL2 | FIP | if it BOOTS | if it FAILS |
|---|---|---|---|---|
| `C` | vendor | vendor | control is sound; card/reader fine | card or reader problem, not our build |
| `A` | **vendor** | **ours** | **our BL2 is the fault** | **our FIP/BL33 is the fault** |
| `B` | **ours** | **vendor** | our FIP is the fault | our BL2 is the fault |
| `O` | ours | ours | — | the observed failing combination |

Run `A` first: it isolates BL2 from FIP in one flash. If `A` boots, the only
remaining suspect is our BL2's init — `atf.nix` builds
`BOOT_DEVICE=sdmmc DRAM_USE_COMB=1`, and if COMBO picks the wrong DDR geometry
for this 4 GB board, BL31 is loaded into memory that is not up yet.

The images themselves are not checked in (vendor firmware is not
redistributable). Produce them next to this script:

    V=/path/to/BPI-R4Pro-4E-...-sdcard-260325.img
    dd if="$V" bs=512 skip=34    count=8158 status=none of=vendor-bl2.img
    dd if="$V" bs=512 skip=13312 count=8192 status=none of=vendor-fip.img
    dd if=/dev/sda bs=512 skip=34    count=8158 status=none of=our-bl2.img
    dd if=/dev/sda bs=512 skip=13312 count=8192 status=none of=our-fip.img
