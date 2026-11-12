{ inputs
, config
, lib
, name
, pkgs
, profiles
, relativeRepo
, ...
}:

# s-nodus-nixos-hardware -- Banana Pi BPI-R4 Pro 4E (MediaTek MT7988A, aarch64).
#
# This is a TEST COPY of nixos/server/s-nodus that takes its board support from
# the esp0xdeadbeef/nixos-hardware fork (module
# `bananapi-bpi-r4-pro`) instead of the host-local board files (boot.nix,
# kernel.nix, dtb.nix).  It exists so the nixos-hardware port can be built and
# compared against the real host WITHOUT changing s-nodus and without risking
# the board: nothing here is deployed, and the hardware identity (hostname,
# nebula cert) is kept equal to s-nodus so the comparison is apples-to-apples.
#
# Differences from s-nodus, by design:
#   * board hardware (kernel, DTB, console, no-NixOS-bootloader) comes from
#     inputs.nixos-hardware-bpi-r4-pro.nixosModules.bananapi-bpi-r4-pro;
#   * the FIT + U-Boot env come from the same module's fit.nix/uboot-env.nix;
#   * the vendor sd-image.nix import is dropped (that image cannot write the
#     vendor BL2/FIP blobs; the nixos-hardware sd-image.nix lays out the GPT and
#     expects a stock OpenWrt card underneath -- see its README).
#
# Named in the fleet's series (s-gamma, s-sigma, s-tau); "nodus" is Latin for
# "knot" -- a box that joins networks. At this stage it is NOT a router: every
# Ethernet port is a DHCP client, nothing forwards. Serial console (ttyS0) is
# the primary access path.
#
# Boots from microSD via the board's stock OpenWrt U-Boot.
let
  # Resolves a checked-in public key under ssh-keys/deadbeef/.
  keyFor = host: lib.fileContents (relativeRepo.sourceModule "ssh-keys/deadbeef/${host}.pub");
in
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    # sd-image.nix: gives us system.build.rootfsImage (sdImage.rootFilesystemImage)
    # so mk-sd-image.sh can dd a ready btrfs root into `nixos-root`.
    # Use inputs.nixpkgs (not config.*) -- referencing config in imports recurses.
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"

    # Board support from the nixos-hardware fork: kernel (6.18 + OpenWrt MT7988
    # net delta), resolved BPI-R4 Pro DTS, serial console, bootargs, the
    # kernel-driver build guard, and the boot chain (BL2 + FIP + U-Boot built
    # from source, then EFI -> systemd-boot).
    inputs.nixos-hardware-bpi-r4-pro.nixosModules.bananapi-bpi-r4-pro
    # U-Boot environment: now only carries `bootcmd=bootflow scan -lb` plus a
    # fallback command line, because the real per-generation kernel cmdline is
    # written by systemd-boot into the ESP by `nixos-rebuild`.
    (inputs.nixos-hardware-bpi-r4-pro + "/bananapi/bpi-r4-pro/uboot-env.nix")

    # Headless board: take the useful base pieces but NOT the desktop/laptop
    # shell profiles (fish/zsh prompt) which drag in shell/user assumptions
    # that don't apply here.
    profiles.nixos.core
    profiles.nixos.base.system
    profiles.nixos.base.maintenance
    profiles.nixos.network.private

    profiles.nixos.impermanence.minimal
    profiles.nixos.ssh.password-login
    # Shared key set (same as l-envil/s-gamma): l-portal, l-esp, s-sigma,
    # s-sigma-root.  Keeps s-nodus reachable by key over the clients VLAN
    # without the serial dev port.
    profiles.nixos.ssh.deadbeef-authorized-keys
    profiles.nixos.users.deadbeef-ssh
    profiles.nixos.users.sudo-nopasswd
    profiles.nixos.shell.zsh-prompt

    # Declares local.users.primary (the zsh-prompt profile resolves the
    # interactive user through it; s-nodus does not import
    # profiles.nixos.base.default, which would normally pull this in).
    (relativeRepo.module "modules/nixos/local-users.nix")

    # Join the nebula overlay (100.64.0.18) so s-nodus can reach -- and
    # offload builds to -- the fleet's remote builders, and read secrets via
    # sops (identity = the persistent ssh host key below).
    inputs.sops-nix.nixosModules.sops
    profiles.nixos.network.nebula-mesh
    profiles.nixos.sops.persist-root-ssh
    profiles.nixos.nix.remote-builder-client

    ./boot.nix
    ./network.nix
    ./cobalt-bridges.nix
    # Host-level Wi-Fi AP (MT7996), reusing the cobalt AP-VM implementation.
    ./wifi-ap.nix
    # NOTE: no ./fit.nix here -- there is no FIT any more.  The boot chain is
    # BL2 + FIP from inputs.nixos-hardware-bpi-r4-pro's bananapi/bpi-r4-pro (fip.nix) and
    # systemd-boot on the ESP (efi.nix).

    # Optional machine-local overrides.  The board keeps its own copy at
    # /etc/nixos.local.nix (mirrored by the rsync deploy) so an on-board
    # rebuild can set nixpkgs.buildPlatform = aarch64-linux and build
    # natively; the checked-in default cross-builds from x86_64 for the
    # card image.  Kept out of this dir so the repo rsync cannot clobber it.
    ./local-overrides.nix

    # Run the aarch64 cobalt router VM here (see ./vm-host.nix for why this is
    # a single-instance config rather than the shared fleet inventory).
    inputs.nixos-shell-vm-manager.nixosModules.default
    ./vm-host.nix

    # Cobalt Tang (NBDE) as a host container instead of a nixos-shell VM.  The
    # VM only ever wrapped this container and cost a whole QEMU process
    # (250 MiB resident + 413 MiB swapped, 2 vCPU) for a ~25 MiB daemon on a
    # 4-core / 3.8 GiB board that also hosts s-router-cobalt-new.  Its key
    # database lives on /persist (not SOPS) so rotation is a file operation.
    ./tang.nix

    # Trial boot entry: runs the candidate cobalt router in place of production
    # and reboots back to the default entry when the window ends.
    ./router-new-test.nix

    # The board's USB-serial console adapter (04d9:b534) needs an explicit
    # driver bind; without it no /dev/ttyUSB* is created.
    ./usb-serial-console.nix

    # The board serves its own kernel/console log over TCP so the console is
    # always reachable, independent of the operator laptop's USB adapter.
    ./kernel-log-tcp.nix
    ./mxl862xx-tagging.nix

    # Reboot the board when BOTH internet probes stay unreachable for the whole
    # window; one reachable target means a DNS/CDN problem, not a dead uplink.
    ./internet-guard.nix

    # microSD layout.  Replicates the vendor GPT geometry (bl2/ubootenv/
    # factory/fip + production FIT + btrfs root) because the MT7988 BootROM,
    # BL2 and the stock U-Boot locate their payloads by fixed sector + GPT
    # name.  Applied with disko --mode disko; also drives fileSystems here.
    (import ./disko.nix { inherit lib; })
  ];

  # Keep the SAME hostname as the real s-nodus (not `name`, which would become
  # "s-nodus-nixos-hardware").  This copy is an identity-equivalent build of the
  # same board: the nebula host cert is issued for s-nodus (overlay 100.64.0.18)
  # and the secrets are keyed under secrets/s-nodus.yaml, so a different
  # hostname would be a different device claiming the same overlay identity.
  # Nothing here is deployed anyway -- the point is to build and compare.
  networking.hostName = lib.mkForce "s-nodus";

  # The board carries many managed bridges whose members are often carrier-less
  # (AP radios before hostapd starts, the cobalt LAN/WAN taps, the dmz/vpn
  # planes). systemd-networkd-wait-online treats every managed link as required
  # unless it opts out, so the boot-time wait expired with
  # "Timeout occurred while waiting for network connectivity" while the host was
  # in fact reachable. Satisfy the target as soon as any managed link is online;
  # units that genuinely need a specific link already order against it.
  # Verified 2026-11-06 on generation vdl5yv7l: `--any` IS in the unit's argv
  # and the unit still times out -- "Timeout occurred while waiting for network
  # connectivity" after 120s -- because no managed link on this board reaches
  # online within that window (the board's own uplink is the router VM it hosts,
  # and the AP/bridge/vlan links are carrier-less at boot). The result is two
  # minutes of boot spent waiting and a unit left in `failed`, which makes the
  # whole host report `degraded` and hides real failures.
  #
  # Nothing here needs the wait: the only consumers are the internet guard (which
  # probes and retries on its own window) and nixos-upgrade. Disable the unit so
  # boot stops depending on guest-facing links.
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  local.internetGuard.enable = true;

  # 4 cores is very little for a box that also forwards a 10G WAN into a VM.
  # Measured with `nix run nixpkgs#fast` on the live prod router:
  #   schedutil : 682-779 Mbps down / 626-627 up
  #   performance: 836 Mbps down / 658 up   (12 ms, best of all variants)
  # RPS was also tried on eth1/taps and was strictly worse (639/454, 42 ms), so
  # it stays disabled. The board is mains-powered, so governor ramp-up latency
  # is not worth the few watts schedutil saves on a saturating uplink.
  #
  # Local fabric capacity, measured 2026-11-05 with iperf3 between netns pairs
  # on the board itself (no WAN involved), 4 parallel streams:
  #   veth pair:                     8.97 Gbits/sec
  #   via br-cobalt-lan (L2 paths):   8.84 Gbits/sec
  # eth1/eth2 negotiate speed=10000 with 0 tx_errors.
  # So the hardware, kernel and bridge paths do ~9 Gbps: the router is not the
  # bottleneck. Against internet test endpoints the same box managed only
  # 67 MB/s one stream and 21-28 MB/s across 4-6 parallel streams (more flows,
  # LOWER aggregate), i.e. the upstream path currently limits everything.
  # Capacity questions must be answered with a local/known-fast peer, never
  # with WAN speedtests.
  #
  # Host baseline, measured on the bare board (not through the VM) so the VM
  # numbers above can be attributed correctly:
  #   curl 100 MiB from proof.ovh.net: 104857600 bytes in 1.24 s = 84.6 MB/s
  #   ~= 677 Mbps as a single TCP stream, load 1.97-2.65 on 4 cores while the
  #   prod VM held ~170-200% CPU.
  # A single stream therefore tops out in the same 700-850 Mbps band with or
  # without the router VM in the path. The remaining ceiling is per-flow, not a
  # misconfiguration: mtk_soc_eth exposes one RX queue (32 TX), `ethtool -l` is
  # unsupported, and the VM forwards on one busy QEMU thread (~148%). Raising it
  # needs vhost-net multiqueue taps (see the vhost-tap-attach host unit) so the
  # guest can use one queue per vCPU instead of a single emulated queue.
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  time.timeZone = "Europe/Amsterdam";

  # Run sops as a systemd unit rather than an activation script.
  #
  # Why: the sops age key lives at /persist/root/.ssh/id_ed25519, and /persist
  # is mounted by systemd from the real fstab.  As an activation script sops
  # runs from initrd-nixos-activation (before switch-root), at which point
  # systemd-sysroot-fstab-check has only brought up / and /nix -- /persist is
  # NOT mounted yet, so the key is unreadable and every secret fails with
  # "0 successful groups required, got 0".  That is not specific to this
  # board: any host whose sops identity lives under /persist and whose sops
  # runs from the activation script has the same ordering problem.
  #
  # With useSystemdActivation the generated unit declares
  # `RequiresMountsFor = cfg.age.sshKeyPaths` and `after = [ "local-fs.target" ]`,
  # so systemd itself waits for /persist before installing secrets.  This is
  # the documented use of the option (sops-nix: "useful to specify additional
  # dependencies ... such as required mountpoints for SOPS key files").
  sops.useSystemdActivation = true;

  # Nebula mesh secrets (same five keys as s-gamma; see secrets/s-nodus.yaml).
  # The host cert is s-nodus's own (100.64.0.18), the CA + lighthouse IPs are
  # the shared mesh values.
  sops.secrets = lib.genAttrs [
    "nebula-ca-crt"
    "nebula-host-crt"
    "nebula-host-key"
    "nebula-lighthouse-public-ip"
    "nebula-cobalt-lighthouse-public-ip"
  ]
    (_: {
      sopsFile = relativeRepo.sourcePath "secrets/s-nodus.yaml";
    });

  # s-nodus is a server-class client: it may offload to the whole builder
  # fleet (s-sigma/s-tau, both serving aarch64-linux), unlike a laptop, which
  # never uses another laptop as a builder.
  local.nix.remoteBuilderClient.class = "server";

  # Persistent SSH host identity, shared with sops (`persist-root-ssh` uses
  # this key as the age identity) -- same arrangement as s-gamma.
  services.openssh.hostKeys = [
    {
      type = "ed25519";
      path = "/persist/etc/ssh/ssh_host_ed25519_key";
    }
  ];

  # Board support (kernel/bootloader/DHCP-everything).
  local.bpiR4Pro.enable = true;

  # zsh as the interactive shell (same profile as s-gamma and the laptops).
  # The board is a headless serial/SSH host, so the prompt reads "server".
  local.shell.zshPrompt.enable = true;

  # Enable the impermanence defaults.  Importing the profile is not enough:
  # it is gated on this option, and without it /persist and /nix never get
  # `neededForBoot` (+ the x-initrd.mount that follows), so they are mounted
  # only in stage 2.  sops-nix runs in the INITRD and reads its age identity
  # from /persist/root/.ssh/id_ed25519, so without this the secrets cannot be
  # decrypted and nebula-mesh has no config to start with.
  profiles.impermanence.minimal.enable = true;

  # Serial console + SSH (password-login profile enables sshd with
  # PermitRootLogin = "no"; the deadbeef-authorized-keys profile supplies the
  # keys).  sshd/gssapi/key-auth all off, so this is key-only for deadbeef.
  services.getty.autologinUser = "root";
  users.users.root.initialPassword = "changeme"; # change on first login

  # Additional key on top of the shared deadbeef-authorized-keys profile
  # (l-portal, l-esp, s-sigma, s-sigma-root): the fleet admin key.  Kept
  # host-local rather than added to the shared profile so the grant stays
  # scoped to this host.
  #
  # No root keys and no PermitRootLogin override: root SSH stays disabled
  # (password-login profile) by design -- deadbeef is in wheel with NOPASSWD
  # sudo below, so root access is unnecessary.
  users.users.deadbeef.openssh.authorizedKeys.keys = [
    (keyFor "admin")
  ];

  # deadbeef in wheel so the sudo-nopasswd profile (NOPASSWD for group wheel)
  # grants passwordless sudo -- same arrangement as l-envil.
  users.users.deadbeef.extraGroups = [ "wheel" ];

  # aarch64 board.
  #
  # buildPlatform is deliberately NOT pinned to x86_64.  It used to be, so the
  # rootfs/kernel could be cross-built on the laptop (mk-sd-image.sh runs
  # there), but that made an ON-BOARD rebuild impossible: the build graph then
  # contained x86_64-linux derivations (boot.json, the toplevel itself) that
  # this aarch64 host cannot build, and with nix.settings.max-jobs = 0 they are
  # only offered to the remote builders -- which are reached over nebula, which
  # needs the secrets from the very rebuild being blocked.
  #
  # Leaving buildPlatform equal to hostPlatform means a rebuild on the board
  # builds natively, which is what actually has to work.  The SD image is still
  # produced the same way it always was: nixpkgs' cross machinery is selected by
  # the eval/build platform pair, and mk-sd-image.sh runs on a host that can
  # satisfy whichever it picks (the builders serve both aarch64 and x86_64).
  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.buildPlatform = lib.mkDefault "aarch64-linux";

  # Enable flakes/nix-command: profiles.nixos.base.system sets
  # accept-flake-config=true, whose generated nix.conf fails validation
  # unless the flakes experimental feature is enabled.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Mostly-remote builds, with a small local allowance.
  #
  # The board has 4 Cortex-A73 cores and 4 GiB of RAM, and the QEMU-inclusive
  # closures it needs (nixos-shell-vm-manager pulls in qemu -> spice/gtk) are
  # far beyond what it can build locally -- an attempt gets SIGKILLed by the OOM
  # killer.  Those must go to the ssh-ng builders from
  # profiles.nixos.nix.remote-builder-client.
  #
  # max-jobs was 0, which sends EVERY derivation to the builders.  That is
  # wrong during bootstrap: the builders are reached over nebula, nebula needs
  # the secrets, and the secrets need a rebuild -- so with no builder reachable
  # the board cannot rebuild itself at all, not even the trivial config
  # derivations (users-groups.json, vconsole.conf).
  #
  # A small allowance lets those tiny derivations build locally while the large
  # ones still go remote on their own merits (they are far slower to build than
  # to send), and a local rebuild now works before nebula is up.  Swap is sized
  # for it: a 64 GiB file on the NVMe root plus zram, see swapDevices below.
  nix.settings.max-jobs = 2;

  # Evaluation of the network-* pipeline happens on this host and needs more
  # memory than the board's 4 GiB: it peaks around 3.3 GiB and an on-board
  # `nixos-rebuild` was OOM-killed at 92% CPU / 84% RSS.
  #
  # Swap is a FILE on the btrfs root, not a partition:
  #
  #   * It costs no partitioning.  The same rootfs serves both stages, so the
  #     swap size can change without re-laying-out any disk -- and the card
  #     keeps its space unallocated, available to grow the root instead.
  #   * btrfs is not a problem: NixOS's swapfile handling detects a btrfs
  #     filesystem and creates the file with `btrfs filesystem mkswapfile`,
  #     which sets the nocow attribute itself.  The old "btrfs refuses a
  #     swapfile" caveat no longer applies.
  #   * Compared with a partition it cannot be forgotten when re-running disko,
  #     and there is one fewer device to keep uniquely labelled.
  #
  # Sized well above RAM: evaluation alone is ~3.3 GiB, and a rebuild adds more
  # on top.  The failure this prevents is a board that OOMs while rebuilding the
  # very system needed to fix it.
  #
  # It lives under /persist, not /var/lib: impermanence wipes the root subvolume
  # on every boot, so a swapfile on / would be recreated each time (and a
  # half-written one would not survive a crash).  /persist is a separate,
  # non-rolled-back subvolume -- the same place the SSH host keys and the VM
  # state live.
  #
  # /persist/swap is its own btrfs subvolume, and services.btrfs.autoScrub
  # below scrubs only the data subvolumes -- never this one.  btrfs checksums
  # every data block, and a live swapfile is rewritten continuously, so
  # scrubbing it reports a constant stream of checksum mismatches that look
  # exactly like corruption.  Keeping it in a separate subvolume is the only
  # supported way to exclude it: `btrfs scrub` has no per-file skip.
  #
  # zramSwap adds fast in-memory compressed swap beneath this at a higher
  # priority, so the common case never touches the disk at all.
  swapDevices = [
    {
      device = "/persist/swap/swapfile";
      # 64 GiB, matching the SSD-backed (not microSD) swap the board is meant
      # to run on.  The larger size removes any OOM risk from evaluating the
      # network pipeline and building the QEMU-inclusive VM closure on the
      # 4 GiB board.  NixOS recreates the existing btrfs swapfile in place.
      size = 65536; # MiB
    }
  ];

  # Scrub the real data, never the swap subvolume.  Listing the mount points
  # explicitly (rather than relying on the "all btrfs mount points" default)
  # keeps /persist/swap out of the set now and if it is ever mounted.
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [
      "/"
      "/nix"
      "/persist"
    ];
    interval = "monthly";
  };

  zramSwap = {
    enable = true;
    memoryPercent = 100;
    priority = 5;
  };

  # Bring-up tooling.
  environment.systemPackages = with pkgs; [
    iproute2
    ethtool
    tcpdump
    usbutils
    pciutils
    dtc
  ];

  # --- rootfs image build ------------------------------------------------
  # Produce a btrfs rootfs image (with /nix + system) so mk-sd-image.sh can
  # dd it into the `nixos-root` partition.  sd-image.nix gives us
  # system.build.sdImage.rootFilesystemImage + system.build.rootfsImage.
  sdImage.compressImage = false;
  sdImage.rootVolumeLabel = "nixos-root";
  # The module defaults to make-ext4-fs.nix; we want btrfs, so point it at the
  # btrfs creator (its option description names this file).
  sdImage.rootFilesystemCreator = pkgs.path + "/nixos/lib/make-btrfs-fs.nix";
  # No FAT firmware partition contents: the ESP is populated by systemd-boot's
  # own builder (BOOTAA64.EFI + loader entries), not by a firmware blob.
  sdImage.populateFirmwareCommands = "";

  # No populateRootCommands: the system profile link is written by
  # mk-sd-image.sh's `populate`, onto the /nix subvolume.
  #
  # It cannot be done here.  This hook writes into the rootfs image's root
  # directory, which `populate` copies into the /root subvolume -- but at runtime
  # /nix is mounted from a SEPARATE (/nix) subvolume that covers /root's nix/
  # directory.  A link written here is therefore shadowed and stage 1 cannot see
  # it: the boot dies at "Find NixOS closure" with the root mounted and looking
  # healthy, which is precisely how this failed.
  #
  # `populate` writes the link onto the subvolume that is actually mounted at
  # /nix, and reads the toplevel out of the image's own store so the target is
  # always present.
  sdImage.populateRootCommands = "";
  sdImage.expandOnBoot = false; # the module's auto-grow is ext4-only

  # Root is btrfs (override the module's ext4 default).
  # disko sets fileSystems."/".device = /dev/disk/by-partlabel/nixos-root;
  # sd-image.nix wants /dev/disk/by-label/nixos-root.  Prefer the PARTLABEL
  # (that is what disko.nix and the FIT bootargs use).
  fileSystems."/".fsType = lib.mkForce "btrfs";
  fileSystems."/".device = lib.mkForce "/dev/disk/by-partlabel/nixos-root";
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  # The FAT firmware partition IS the ESP now: U-Boot's EFI loader reads
  # EFI/BOOT/BOOTAA64.EFI from it and systemd-boot takes over.  This reverses
  # the old "no ESP" arrangement, which existed only because the vendor U-Boot
  # had no bootefi path.  Mount point is set by efi.nix (efiSysMountPoint=/boot).
  fileSystems."/boot/firmware".options = lib.mkForce [ "nofail" "noauto" ];

  # sd-image force-enables enableAllHardware (a generic initrd module list for
  # portable images), which pulls modules this board disables and breaks initrd
  # assembly.  Use the board's actual modules instead.
  #
  # The NVMe modules are load-bearing: the root filesystem lives on the Samsung
  # (see ./disko.nix).  Without nvme/nvme-core the block device never appears in
  # stage 1, `by-partlabel/nixos-root` is never created, and the boot dies in
  # emergency mode with "Timed out waiting for device".  mmc_block is built into
  # the kernel, so the boot chain needs nothing extra.
  hardware.enableAllHardware = lib.mkForce false;
  # Module names must match what this kernel actually ships: `nvme` IS the PCI
  # driver here (there is no separate nvme-pci.ko), and it depends on
  # nvme-core.  No `ahci` -- the board has no SATA.
  #
  # The PCIe *host controller* and *PHY* modules are equally load-bearing and
  # were the actual reason the NVMe never appeared: `nvme.ko` alone cannot see
  # a device that no PCIe bus has enumerated.
  #
  # `phy-mtk-xsphy` specifically drives xs-phy@11e10000, whose port 3 IS the
  # PCIe PHY for pcie@11280000 -- the controller the SSD sits on
  # (`phys = <&xphyu3port0 PHY_TYPE_PCIE>` in mt7988a.dtsi).  Without it that
  # controller never probes and logs NOTHING AT ALL -- unlike its siblings it
  # does not even report "link down", because the driver is still waiting on an
  # unsatisfied PHY dependency.  The vendor firmware shows the difference:
  #
  #   mtk-xsphy soc:xphy@11e10000: failed to get ref_clk(id-1)   <- defers
  #   phy phy-soc:xphy@11e10000.3: type_sw - reg 0x218, index 0   <- comes up
  #
  # and then 11280000 probes a second time and links.  Ours had neither line.
  boot.initrd.availableKernelModules = [
    "btrfs"
    "nvme"
    "nvme-core"
    "pcie-mediatek-gen3"
    "phy-mtk-pcie"
    "phy-mtk-xsphy"
  ];

  # Wi-Fi: the on-board MT7996 (BE14, Wi-Fi 7) is a PCIe card in an M.2/miniPCIe
  # slot (PCIe 0000:01:00.0 primary + 0001:01:00.0 secondary).  It needs the
  # linux-firmware mediatek/mt7996/*.bin blobs; without them the driver loads but
  # probe fails with:
  #   mt7996e 0000:01:00.0: Direct firmware load for
  #   mediatek/mt7996/mt7996_rom_patch_233.bin failed with error -2
  # enableRedistributableFirmware pulls in pkgs.linux-firmware (which carries
  # mediatek/mt7996/) and the regulatory database.  The slot POWER is a hardware
  # dipswitch, not software (a board DIP in the wrong position left the slots at
  # "detect.quiet" with no card enumerated).
  hardware.enableRedistributableFirmware = true;

  # Allow an unauthenticated shell in the stage-1 emergency mode.
  #
  # Without this, `emergencyAccess` defaults to false and systemd's sulogin
  # refuses with "Cannot open access to console, the root account is locked" --
  # which makes a failed boot undebuggable from the serial console even though
  # the box is physically in front of you.  With it, a failure at
  # initrd-find-nixos-closure (or anything else in stage 1) drops to a root
  # shell where /sysroot is already mounted, so the cause can be inspected and
  # fixed in place instead of pulling the storage out.
  #
  # Stage 2 is unaffected: `systemd.enableEmergencyMode` is a separate option
  # and stays at its default.  Physical console access is already required to
  # reach this shell, so this does not widen the threat model.
  boot.initrd.systemd.emergencyAccess = true;

  # Expose the rootfs image under a stable attribute for mk-sd-image.sh.
  system.build.rootfsImage = config.sdImage.rootFilesystemImage;

  system.stateVersion = "26.05";
}
