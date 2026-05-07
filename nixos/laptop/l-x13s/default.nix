{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  outPath,
  ...
}:
{
  imports = [
    ./wifi.nix

    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./packages/packages.nix
    ./packages/widevine.nix

    # X13s-only nixos-hardware branch:
    # https://github.com/NixOS/nixos-hardware/pull/1751
    inputs.nixos-hardware-x13s.nixosModules.lenovo-thinkpad-x13s

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager

    # inputs.nixos-x13s.nixosModules.default
    "${outPath}/library/02-window-manager-i3/default.nix"

    "${outPath}/library/01-general/system/garbage-collection.nix"
    "${outPath}/library/01-general/system/autoupdate.nix"
    "${outPath}/library/01-general/desktop/fonts.nix"

    #"${outPath}/library/01-general/desktop/shell-env.nix"
    ./fish.nix

    inputs.sops-nix.nixosModules.sops
  ];
  sops.defaultSopsFile = ../../../secrets/l-x13s-default.yaml;
  sops.age.sshKeyPaths = [ "/persist/root/.ssh/id_ed25519" ];
  sops.age.keyFile = "/persist/root/.config/sops/age/keys.txt";
  sops.secrets."deadbeef-passwd" = {
    neededForUsers = true; # make it available before the user is created
  };
  time.timeZone = "Europe/Amsterdam";

  home-manager = {
    sharedModules = [
      inputs.sops-nix.homeManagerModules.sops
    ];
    extraSpecialArgs = {
      inherit inputs outputs;
    };

    users = {
      deadbeef = import ../../../home-manager/l-x13s/home.nix;
    };
  };

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # Widevine patch.
      inputs.nixos-aarch64-widevine.overlays.default
    ];

    config = {
      allowUnfree = true;
    };

    hostPlatform = "aarch64-linux";
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = "nix-command flakes";

        # Opinionated: disable global registry.
        flake-registry = "";

        # Workaround for:
        # https://github.com/NixOS/nix/issues/9574
        nix-path = config.nix.nixPath;
      };

      # Opinionated: disable channels.
      channel.enable = false;

      # Opinionated: make flake registry and nix path match flake inputs.
      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  networking.hostName = "l-x13s";
  networking.networkmanager.enable = true;
  services.autorandr.enable = lib.mkForce false;
  security.rtkit.enable = true;
  hardware.enableRedistributableFirmware = true;

  users.mutableUsers = false;

  users.users = {
    deadbeef = {
      #initialPassword = " ";
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      isNormalUser = true;

      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
      ];

      extraGroups = [
        "wheel"
      ];
    };
  };

  services.openssh = {
    enable = true;

    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  system.stateVersion = "24.11";
}
