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

    # microSD layout.  Replicates the vendor GPT geometry (bl2/ubootenv/
    # factory/fip + production FIT + btrfs root) because the MT7988 BootROM,
    # BL2 and the stock U-Boot locate their payloads by fixed sector + GPT
    # name.  Applied with disko --mode disko; also drives fileSystems here.
    (import ./disko.nix { })
  ];

  networking.hostName = lib.mkForce name;
  time.timeZone = "Europe/Amsterdam";

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

  # aarch64 board.  buildPlatform is set so the rootfs/kernel can also be
  # cross-built on the x86_64 host (mk-sd-image.sh runs there); without it the
  # rootfs derivation is aarch64-only and fails with "platform mismatch".
  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  # Enable flakes/nix-command: profiles.nixos.base.system sets
  # accept-flake-config=true, whose generated nix.conf fails validation
  # unless the flakes experimental feature is enabled.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
  sdImage.populateRootCommands = "";
  sdImage.expandOnBoot = false; # the module's auto-grow is ext4-only

  # Root is btrfs (override the module's ext4 default).
  # disko sets fileSystems."/".device = /dev/disk/by-partlabel/nixos-root;
  # sd-image.nix wants /dev/disk/by-label/nixos-root.  Prefer the PARTLABEL
  # (that is what disko.nix and the FIT bootargs use).
  fileSystems."/".fsType = lib.mkForce "btrfs";
  fileSystems."/".device = lib.mkForce "/dev/disk/by-partlabel/nixos-root";
  boot.initrd.supportedFilesystems = [ "btrfs" ];

  # sd-image force-enables enableAllHardware (a generic initrd module list for
  # portable images), which pulls modules this board disables and breaks initrd
  # assembly.  Use the board's actual modules (MMC is built-in; btrfs for root).
  hardware.enableAllHardware = lib.mkForce false;
  boot.initrd.availableKernelModules = [ "btrfs" ];

  # Expose the rootfs image under a stable attribute for mk-sd-image.sh.
  system.build.rootfsImage = config.sdImage.rootFilesystemImage;

  system.stateVersion = "26.05";
}
