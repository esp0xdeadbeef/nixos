{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:
{
  imports = [
    ../../../library/02-window-manager-i3/default.nix

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
  ];

  home-manager = {
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

  users.users = {
    deadbeef = {
      initialPassword = " ";
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
