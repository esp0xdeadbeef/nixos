{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  name,
  outPath,
  modulesPath,
  ...
}:

let
  codexUser = "deadbeef";
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")

    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops

    "${outPath}/library/01-general/system/garbage-collection.nix"
    "${outPath}/library/01-general/system/autoupdate.nix"

    ./codex
    ./disko.nix
  ];

  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  networking.hostName = "codex-jail";

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];

    config.allowUnfree = true;
    hostPlatform = "x86_64-linux";
  };

  nix =
    let
      flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
    in
    {
      settings = {
        experimental-features = "nix-command flakes";
        flake-registry = "";
        nix-path = config.nix.nixPath;
      };

      channel.enable = false;

      registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
      nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    };

  sops.defaultSopsFile = "${outPath}/secrets/${name}.yaml";
  sops.secrets.deadbeef-passwd.neededForUsers = true;

  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  boot.loader.grub.enable = lib.mkForce true;
  boot.loader.grub.efiSupport = lib.mkForce false;
  boot.loader.grub.device = lib.mkForce "nodev";
  boot.loader.grub.devices = lib.mkForce [ ];
  boot.loader.grub.mirroredBoots = lib.mkForce [
    {
      devices = [ "/dev/vda" ];
      path = "/boot";
    }
  ];
  boot.loader.grub.useOSProber = lib.mkForce false;

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "sd_mod"
    "sr_mod"
  ];

  fileSystems."/boot".neededForBoot = true;
  fileSystems."/persist".neededForBoot = true;

  systemd.tmpfiles.rules = [
    "d /persist/etc 0755 root root -"
    "d /persist/etc/ssh 0755 root root -"
  ];

  users.mutableUsers = false;

  users.users = {
    root = {
      hashedPassword = "!";
    };

    deadbeef = {
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.deadbeef-passwd.path;
      extraGroups = [ "wheel" ];

      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
      ];

      shell = pkgs.zsh;
    };
  };

  services.openssh = {
    enable = true;

    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        bits = 4096;
        type = "rsa";
      }
    ];

    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = true;
    };
  };

  services.getty.autologinUser = lib.mkForce "deadbeef";
  services.displayManager.autoLogin.enable = lib.mkForce false;

  security.sudo.enable = true;
  security.sudo.extraRules = [
    {
      groups = [ "wheel" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    git
    vim
    neovim
    tmux
    curl
    wget
    jq
    ripgrep
    fd
    htop
    pciutils
    usbutils
    lsof
    file
    gcc
    gdb
    python3
    nodejs
  ];

  programs.zsh.enable = true;

  environment.interactiveShellInit = ''
    ZSH_THEME=agnoster
  '';

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;

  home-manager.users.${codexUser} = {
    programs.zsh = {
      enable = true;
    };

    home.stateVersion = "25.11";
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/log"
      "/home/deadbeef"
    ];

    files = [
      "/etc/machine-id"
    ];
  };

  system.stateVersion = "25.11";
}
