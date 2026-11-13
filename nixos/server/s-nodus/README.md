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

The card carries **only the boot chain**. It deliberately has no root
filesystem: that lives on the first NVMe (below), whose layout is

| # | PARTLABEL | Size | FS | Role |
|---|---|---|---|---|
| 1 | `nixos-root` | disk − swap | btrfs (`/root`,`/nix`,`/persist`) | `/` |
| 2 | `swap` | `swapSizeGiB` (64 GiB) | swap | paging |

`bl2`/`fip` are signed vendor blobs; `production` holds the FIT. The `nixos-root`
btrfs label/PARTLABEL is what the FIT's bootargs resolve.

`nixos-root` must be **unique across all attached disks**. The card used to
carry a `nixos-root` partition of its own, and while both existed
`/dev/disk/by-partlabel/nixos-root` resolved to whichever udev happened to
settle last -- which mounted the wrong root and dropped the board into an
emergency shell. The card's copy is now named `sd-old-root` (and holds no
root); leave it that way.

Swap is sized by the `swapSizeGiB` argument (default 64 GiB). The board has
only 4 GiB of RAM, and evaluating the network pipeline peaks near 3.3 GiB, so
swap is what keeps a heavy build from being OOM-killed.

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

## Reaching the NVMe root from another machine (NBD)

The board's root lives on the NVMe, and the card only carries the boot chain
(see [Storage](#storage-diskonix)). To partition or populate that root from a
laptop — instead of pulling the drive or running everything on the 4 GiB
board — export the partition over NBD from the board and mount it remotely.

The board's serial console is the reliable way in: it runs the stock OpenWrt,
which already ships `nbd-server` (`nbd-server - 3.25-r1` via `opkg`).

**1. Export the partition from the board**, bound to the LAN address. The
`[ip:]port file` form matters:

```sh
# on the board (serial console)
nbd-server 192.168.1.1:10809 /dev/nvme0n1p1 >/tmp/nbd.log 2>&1 &
netstat -lnt | grep 10809      # want: 192.168.1.1:10809  0.0.0.0:*  LISTEN
```

Always pass the `192.168.1.1:` prefix. Without it `nbd-server` listens on
**every** interface (`:::10809`) — the board's WAN side included — and the
ancient NBD export protocol has no authentication, so that would expose the
root filesystem to the uplink. Kill a stray server with `killall nbd-server`
(there is no `pkill` on OpenWrt).

**2. Attach it from the laptop:**

```sh
modprobe nbd max_part=8                      # creates /dev/nbd0
nix shell nixpkgs#nbd -c nbd-client 192.168.1.1 10809 /dev/nbd0
blkid /dev/nbd0        # want LABEL="nixos-root" TYPE="btrfs"
mount -t btrfs /dev/nbd0 /mnt/snodus
btrfs subvolume list /mnt/snodus
```

Use `nbd-client`, not `qemu-nbd`. `qemu-nbd` is the fallback everyone reaches
for because it is often the only NBD tool installed, but its client mode has no
export-name option (`-N` is an `nbd-client` flag; `qemu-nbd` rejects it) and it
does not survive the newstyle negotiation `nbd-server` 3.25 uses — it connects
and immediately disconnects, leaving `/dev/nbd0` without a filesystem.
`nix shell nixpkgs#nbd` provides `nbd-client` without installing anything, and
that connects first time:

```
Negotiation: ..size = 976761MB
Connected /dev/nbd0
/dev/nbd0: LABEL="nixos-root" ... TYPE="btrfs"
```

Listing exports is refused by the server (`E: listing not allowed by server.`),
which is fine — the default export is the device that was passed on the
command line.

Detach when done, otherwise the board's server keeps the device busy:

```sh
umount /mnt/snodus && nbd-client -d /dev/nbd0
```

**Network reality check.** The board has *no* route to the nebula builders
(`ping 100.64.0.17` → 100% packet loss), but it is reachable on the LAN
(`192.168.1.x`, ~1.3 ms). So a laptop that is on the LAN *and* on the mesh is
the bridge: it can mount the board's NVMe and still reach s-tau/s-sigma for
the closure.

Do not try to `dd` the raw image over this link: the image is ~25 GiB because
it declares a 24 GiB `nixos-root`, of which the card needs only the first
~1 GiB (see `mk-sd-image.sh flash`, which copies just the boot chain).

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

## LAN ports and the cobalt trunk

s-nodus feeds the `s-router-cobalt-new` VM through host-private L2 bridges
(`./cobalt-bridges.nix`). The host itself has no address on them; the VM owns
all routing/NAT (`./network.nix`).

### Port map

The MT7988 internal switch exposes exactly **four** PHY ports. Port 0 is the
board's `lan5` management port (DHCP, host uplink/nebula); ports 1-3 are
disabled by the mainline board dtsi and re-enabled here as `lan1`/`lan2`/`lan3`.
There is **no `lan4`** -- the switch has no fifth port.

Both the device-tree overlay and the networkd rules are generated from the
single map in `./lan-port-map.nix`, so a port's DT label and its role cannot
drift apart:

| netdev | role | bridge |
|---|---|---|
| `mxl_lan0` | 802.1Q trunk (tagged) | `br-cobalt-lan` |
| `mxl_lan1` | untagged access | `vlan50` |
| `mxl_lan2` | untagged access | `vlan50` |
| `mxl_lan3` | untagged clients access | `vlan30` |
| `lan5` | management (DHCP) | not bridged |

`br-cobalt-lan` terminates the access VLANs off the trunk (`cobalt-lan.30`,
`cobalt-lan.50`) into the untagged `vlan30`/`vlan50` bridges that the access
jacks join. The cobalt VM attaches its LAN NIC to `br-cobalt-lan` and its WAN
NIC to `br-cobalt-wan`; it starts only while the WAN SFP is present
(`./vm-host.nix`), but `mxl_lan0` stays wired regardless.

Every 2.5G jack on this board is `mxl_lanN` (the mainline DSA port labels),
not the bare `lanN` of the vendor DTS. All four jacks currently report
`carrier=0` on the running host, i.e. **no cable is plugged into any of them**
-- `NO-CARRIER`/`lowerlayerdown` on `mxl_lanN` is a physical fact, not a
plumbing bug. Their bridge membership is what the map below sets, and it is
correct whether or not a cable is present. Plug a device into `mxl_lan1`-`3`
after wiring the trunk and it lands on the mapped plane.

Because the VM terminates the VLANs itself, the access jacks reach the router
only through the trunk: with `mxl_lan0` unplugged, `vlan50` has no uplink into
the VM and its jacks see link but never get DHCP. Wire `mxl_lan0` to the cobalt
router's switch trunk before expecting the access jacks to pass traffic.

The clients plane is shared by three things -- this host's own
management/underlay address, the `cobalt-clients` AP BSS, and the `mxl_lan3`
access jack -- all on `vlan30`. That is why `mxl_lan1`/`mxl_lan2` are on
`vlan50` (`cobalt-iot`, its own `10.2.50.0/24`) and not `vlan30`: a VLAN-30
device would otherwise share L2 with the host and the AP clients.

### Verifying the trunk

`mxl_lan3` is a **bridge member** of `vlan30`. `tcpdump -i mxl_lan3` can miss
frames the bridge forwards straight through to another port, so a blank
capture there is not proof that nothing arrives. Capture on the bridge or the
VLAN child instead, and confirm the link state first:

```sh
ip -br link show mxl_lan3              # must not be NO-CARRIER
bridge link show                      # mxl_lan3 should be a member of vlan30
ip -br link show master br-cobalt-lan # members (plus the VM tap when it runs)
tcpdump -i br-cobalt-lan -n -e        # tagged VLAN 30 frames crossing the bridge
tcpdump -i cobalt-lan.30 -n -e        # the same frames after tag termination
```

The cobalt clients plane is `10.2.30.0/24`, gateway `10.2.30.1` (the VM), DHCP
pool `10.2.30.100-200`. To prove the switch trunk is configured correctly
without the VM, put a transient VLAN-30 address on the trunk and ping a known
VLAN-30 peer:

```sh
# transient; not persisted. The bridge stays unaddressed otherwise.
ip link add link br-cobalt-lan name t30 type vlan id 30
ip addr add 10.2.30.250/24 dev t30
ip link set t30 up
ping -c3 10.2.30.1                    # or any live VLAN-30 host
ip link del t30
```

If `tcpdump -i br-cobalt-lan -e` shows tagged VLAN-30 frames but the ping does
not answer, the L2 path is fine and the problem is L3 (no VLAN-30 peer up). If
the bridge capture is empty too, nothing is arriving from the switch: check
that the switch port is a matching 802.1Q trunk (ports 1-2 carry VLAN 30
tagged; `prod-network/cobalt/switch-vlan.toml`) and that lan1 has carrier.

## Wi-Fi (`wifi-ap.nix`)

The on-board MT7996 (Wi-Fi 7, tri-band) runs hostapd **on the host**, reusing
the cobalt AP-VM implementation (`wifi-ap.nix` + `wifi-ssids.nix`) rather than
passing the radio into a VM (an on-die PCIe device cannot be passed through the
way the USB AP dongles are). It advertises every cobalt intent plane on every
band that can carry it:

| plane                | 2.4 GHz | 5 GHz | 6 GHz |
|----------------------|:-------:|:-----:|:-----:|
| `cobalt-clients`     |   yes   |  yes  |  yes  |
| `cobalt-clients-vpn` |   yes   |  yes  |  yes  |
| `cobalt-mgmt`        |   yes   |  yes  |   -   |
| `cobalt-unlock`      |   yes   |  yes  |   -   |

The two WPA-PSK planes are 2.4/5 GHz only: 6 GHz forbids pre-RSNA security, so
only the SAE planes can be advertised there. Each plane's BSS bridges onto the
same tenant the wired ports use (`vlan30` / VLAN 31 / 10 / 90 off the
`br-cobalt-lan` trunk), so a Wi-Fi client lands on the same `10.2.30.0/24` as a
wired one. SSIDs are the site-wide derived ones from `secrets/cobalt-wifi`.

Debugging:

```sh
systemctl status 'ap-wlp*'                # one unit per BSS
journalctl -u ap-wlp1s0.service -n50      # hostapd log for one BSS
cat /run/ap/wlp1s0.conf                   # generated hostapd config
cat /run/ap/ssids.env                     # derived SSIDs (shared across bands)
```

Gotchas baked into the builder: the MT7996 exposes a single netdev, so each
band's base AP interface (`wlp1s-5`, `wlp1s-6`) is created on `phy0` first; all
VAPs otherwise share the base MAC and the kernel refuses to bring up more than
one (`Name not unique on network`), so each VAP gets a distinct
locally-administered MAC. If `ap-conf-*` fails with an empty SSID, `/run/ap`
was cleared — restart `ap-ssid-*` to regenerate `ssids.env`.

`ap-planes.service` creates the `ap-mgmt` / `ap-clients-vpn` / `ap-unlock`
bridges and their `cobalt-lan.{10,31,90}` children, and it waits for the trunk
bridge (`br-cobalt-lan`) *inside* its script. It must not carry a
`requires`/`after` on `sys-subsystem-net-devices-br-cobalt-lan.device`: that
bridge is a runtime networkd netdev, so its device unit does not exist when
systemd builds the boot transaction, and a `Requires=` on it fails the job at
transaction time (observed as `Dependency failed for ap-planes.service` after
the device had already plugged). When that job fails, the three extra plane
bridges never appear, every BSS on them loops in `start-pre` waiting for
`state UP`, and `ap-vap-extra` (which requires `ap-planes`) also fails — so
5/6 GHz loses its `wlp1s-5`/`wlp1s-6` base interfaces too. If only the
`cobalt-clients` BSS (on `vlan30`) is running, look at
`systemctl status ap-planes ap-vap-extra` first.

## TODOs / hardening

- [ ] Replace `initialPassword` with a proper credential (sops/keys).
- [ ] Add a `recovery` partition + second FIT so the stock U-Boot's
      `boot_recovery` path works.
- [ ] 10G switch / SFP+ / Wi-Fi via an OpenWrt-delta kernel (see ly4096x port).
