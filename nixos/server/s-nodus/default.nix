{ inputs
, config
, lib
, name
, pkgs
, profiles
, relativeRepo
, ...
}:

# s-nodus -- Banana Pi BPI-R4 Pro 4E (MediaTek MT7988A, aarch64).
#
# Named in the fleet's series (s-gamma, s-sigma, s-tau); "nodus" is Latin for
# "knot" -- a box that joins networks. At this stage it is NOT a router: every
# Ethernet port is a DHCP client, nothing forwards. Serial console (ttyS0) is
# the primary access path.
#
# Boots from microSD via the board's stock OpenWrt U-Boot. Board support is
# mainline (kernel >= 6.19); no vendor/decompiled DTB is vendored.
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    # sd-image.nix: gives us system.build.rootfsImage (sdImage.rootFilesystemImage)
    # so mk-sd-image.sh can dd a ready btrfs root into `nixos-root`.
    # Use inputs.nixpkgs (not config.*) -- referencing config in imports recurses.
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image.nix"

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

    # Join the nebula overlay (100.64.0.18) so s-nodus can reach -- and
    # offload builds to -- the fleet's remote builders, and read secrets via
    # sops (identity = the persistent ssh host key below).
    inputs.sops-nix.nixosModules.sops
    profiles.nixos.network.nebula-mesh
    profiles.nixos.sops.persist-root-ssh
    profiles.nixos.nix.remote-builder-client

    ./boot.nix
    ./dtb.nix
    ./network.nix
    ./fit.nix

    # Optional machine-local overrides.  The board keeps its own copy at
    # /etc/nixos.local.nix (mirrored by the rsync deploy) so an on-board
    # rebuild can set nixpkgs.buildPlatform = aarch64-linux and build
    # natively; the checked-in default cross-builds from x86_64 for the
    # card image.  Kept out of this dir so the repo rsync cannot clobber it.
    ./local-overrides.nix

    # Run the aarch64 cobalt router VM here (see ./vm-host.nix for why this is
    # a single-instance config rather than the shared fleet inventory).
    inputs.nixos-shell-vm-manager.nixosModules.default
    # ./vm-host.nix  # TEMP: disabled to get a clean rebuild (s-router-cobalt-new VM cycle)

    # microSD layout.  Replicates the vendor GPT geometry (bl2/ubootenv/
    # factory/fip + production FIT + btrfs root) because the MT7988 BootROM,
    # BL2 and the stock U-Boot locate their payloads by fixed sector + GPT
    # name.  Applied with disko --mode disko; also drives fileSystems here.
    (import ./disko.nix { inherit lib; })
  ];

  networking.hostName = lib.mkForce name;
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

  # 100% remote builds.  The board has 4 Cortex-A73 cores and 4 GiB of RAM,
  # and the QEMU-inclusive closures it needs (nixos-shell-vm-manager pulls in
  # qemu -> spice/gtk) are far beyond what it can build or even evaluate
  # locally -- a local build attempt gets SIGKILLed by the OOM killer.
  # max-jobs = 0 disables local build jobs entirely, so every derivation goes
  # to the ssh-ng builders from profiles.nixos.nix.remote-builder-client
  # (s-sigma/s-tau, which serve aarch64-linux).  Substitution still happens
  # locally.  If no builder is reachable, builds fail loudly rather than
  # wedging the board.
  nix.settings.max-jobs = 0;

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
      size = 8192; # MiB
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
  # No FAT firmware partition: the FIT (fit.nix) is the boot artifact, and the
  # ESP/FAT path does not exist on this board's vendor U-Boot.
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

  # sd-image.nix always declares a FAT /boot/firmware partition; this board has
  # none (the FIT is the boot artifact, there is no ESP).  The entry cannot be
  # removed, so mark it nofail+noauto -- it is then never touched at boot.
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
