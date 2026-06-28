# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{ inputs
, outputs
, lib
, config
, pkgs
, profiles
, outPath
, ...
}:
let
  hostName = builtins.baseNameOf (builtins.dirOf __curPos.file);
in
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
    profiles.nixos.boot.secure-boot-tools
    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.common-cpu-intel
    inputs.nixos-hardware.nixosModules.common-gpu-intel
    inputs.nixos-hardware.nixosModules.common-gpu-nvidia
    inputs.nixos-hardware.nixosModules.common-pc-laptop
    inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
    profiles.nixos.impermanence.module
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops

    profiles.nixos.workstation.full
    profiles.nixos.desktop.i3
    # profiles.nixos.desktop.sway
    profiles.nixos.boot.usb-removable
    profiles.nixos.hardware.clock-sync
    profiles.nixos.laptop.default
    profiles.nixos.workstation.android
    profiles.nixos.workstation.pentesting
    profiles.nixos.llm.ollama-base
    profiles.nixos.llm.open-webui
    profiles.nixos.containers.firefox-vnc

    ./1-custom-packages/burp-fix.nix
    ./hardware/audio-and-bluetooth.nix
    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./hardware/nvidia.nix
    ./hardware/sound-fix.nix
    ./hardware/swap-and-tmpfs.nix
    ./disko/build_disko.nix
    ./llms/ollama.nix
    ./lxc/bind-to-lxc.nix
  ];

  security.pam.services.login.enableGnomeKeyring = true;
  local.network.private.enable = false;
  local.workstation.android.enable = true;

  sops.defaultSopsFile = "${outPath}/secrets/${hostName}-default.yaml";
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";

  home-manager = {
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit
        inputs
        outPath
        outputs
        profiles
        ;
      primaryUserHome = config.local.users.primary.homeDirectory;
      primaryUser = config.local.users.primary.resolvedName;
    };
    users = {
      ${config.local.users.primary.resolvedName} = import "${outPath}/home-manager/${hostName}/home.nix";
    };
  };

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      cudaCapabilities = [ "8.6" ];
      cudaForwardCompat = false;
    };
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        # Enable flakes and new 'nix' command
        experimental-features = "nix-command flakes";
        # Opinionated: disable global registry
        flake-registry = "";
        # Workaround for https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
      };
      # Opinionated: disable channels
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  # FIXME: Add the rest of your current configuration

  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  warnings = [
    "l-envil: systemd-hibernate.service disables systemd's user.slice freezer because hibernate froze immediately after freezing user.slice; remove this once the upstream/systemd sleep-stack issue is fixed."
  ];
  environment.etc."systemd/sleep.conf.d/10-hibernate-shutdown-mode.conf".text = ''
    [Sleep]
    HibernateMode=shutdown
  '';
  systemd.services.systemd-hibernate.environment.SYSTEMD_SLEEP_FREEZE_USER_SESSIONS = "false";
  hardware.intelgpu.vaapiDriver = "intel-media-driver";
  local.users.primary.name = "deadbeef";
  local.laptop.monitorLayouts.samsungLu28r55Desk = {
    enable = true;
    left = "edid:37a85fea39fa278b";
    right = "edid:ccc5757174dd0f67";
    targetResolution = "3840x2160";
    internalScale = "0.75x0.75";
  };

  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };

  users.users = {
    deadbeef = {
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      isNormalUser = true;
      openssh.authorizedKeys.keys = [ ];
      extraGroups = [ "wheel" ];
    };
  };

  environment = {
    systemPackages = [
      pkgs.mxbuild
      (pkgs.writeShellScriptBin "qemu-system-x86_64-uefi" ''
        qemu-system-x86_64 \
          -bios ${pkgs.OVMF.fd}/FV/OVMF.fd \
          "$@"
      '')
    ];
  };
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.11";
}
