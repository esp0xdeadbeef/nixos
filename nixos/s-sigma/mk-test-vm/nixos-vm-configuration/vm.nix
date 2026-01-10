{
  lib,
  config,
  pkgs,
  ...
}:

{

  virtualisation.qemu.networkingOptions = [
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
    #"-netdev user"
  ];

  virtualisation = {
    cores = 42; # number of vCPUs
    memorySize = 16384; # MB
    diskSize = 20 * 1024;
  };
  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist/minecraft" = /persist/minecraft;
      "/var/lib/containers/storage" = /var/lib/containers/storage;
    };
  };

  imports = [
    ./network.nix
    ./debug-packages.nix
    ./minecraft-services.nix
  ];

  system.stateVersion = "25.11";

  ############################################################
  # Boot (EFI, image-friendly)
  ############################################################
  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;

  boot.loader.efi = {
    canTouchEfiVariables = false;
    efiSysMountPoint = "/boot";
  };

  ############################################################
  # Console / serial
  ############################################################
  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  systemd.services."serial-getty@ttyS0".enable = true;

  ############################################################
  # Networking / access
  ############################################################
  services.openssh.enable = true;

  ############################################################
  # Users
  ############################################################
  users.users.deadbeef = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
    ];
    initialPassword = "";
  };

  services.getty.autologinUser = lib.mkForce "deadbeef";
  services.getty.autologinOnce = true;

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

  services.displayManager.autoLogin.user = "deadbeef";
}
