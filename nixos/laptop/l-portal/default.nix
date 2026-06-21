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
    profiles.nixos.base.default
    profiles.nixos.laptop.default
    profiles.nixos.boot.usb-removable

    inputs.disko.nixosModules.disko

    ./hardware/bootloader.nix
    ./hardware/hardware-configuration.nix
    ./hardware/impermanence.nix
    ./disko.nix
    ./packages/packages.nix
    ./packages/widevine.nix

    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x13s

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager

    # inputs.nixos-x13s.nixosModules.default
    "${outPath}/library/02-window-manager-i3/default.nix"

    "${outPath}/library/01-general/system/garbage-collection.nix"
    "${outPath}/library/01-general/system/autoupdate.nix"
    "${outPath}/library/01-general/desktop/fonts.nix"

    #"${outPath}/library/01-general/desktop/shell-env.nix"

    inputs.sops-nix.nixosModules.sops
  ];
  sops.defaultSopsFile = "${outPath}/secrets/${hostName}-default.yaml";
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
      inherit inputs outputs outPath;
    };

    users = {
      deadbeef = import "${outPath}/home-manager/${hostName}/home.nix";
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

  networking.hostName = hostName;
  networking.networkmanager.enable = true;
  services.autorandr.enable = lib.mkForce false;
  local.laptop.xlayoutdisplayHotplug.maxExternalMode = "2560x1440";
  security.rtkit.enable = true;
  hardware.enableRedistributableFirmware = true;

  specialisation.manual-unlock.configuration = {
    local.boot.clevisTangUnlock.enable = lib.mkForce false;
  };

  users.mutableUsers = false;

  users.users = {
    deadbeef = {
      #initialPassword = " ";
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      isNormalUser = true;

      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNntUmNyQ+OYSEGHlXSBOQSWsJkXnx8E+zhfhGFRDuy deadbeef@l-portal"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPqHQoNlgpqtFtwDfWXqnxk8+4BPS0nrOGQrlarOvneo deadbeef@l-esp"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCiusRhQSFtAGfHuewHQSANtEUP6nQu1S3LVoR/BEs7Fs8u6x8nRZnlQo1+skfjNWvV/5d76CPvUFP228mdhPWYYtkE1Vy+pLAq1UhPuJjOJKgac8MvR4veRyRTAQIWGdmEPa/XKKgekjYT2OKHkHibM2apbg5pFNdFAHSI8Oy7vqSmSVCKVzyoISoChkFpM02+guYS/J8ysyGNj+LW+C3shiwdYfRCnHdsjc9EjWUb++PIDhKwmeHK5yqPffKuc6kE8v9kTXx9JEeP/MQ9f6vZZbChPl71QiEt7Bt22lXiRfatvrdMqHyL7qCs4vFY+pkeY9V1tN2WPnuwcQJRNR2KRtznGMHIg6Sfwd2MT7XQyEoW3VH0m53AoljI/VdYWpUAdfVtNIOvG2BrKwfbZuiPXCPZDXy8zkovO/MO0ux62DLm+hBf103NZWd23P+yAfEyFoa0909NZiyfUtBAzudj69sKTeSwQRR3p8ZoNQfjCvcWvvtcAUpLk54Z+iFuRAc= deadbeef@l-esp"
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
