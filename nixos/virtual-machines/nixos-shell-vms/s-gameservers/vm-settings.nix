{
  lib,
  config,
  pkgs,
  ...
}:

{

  nixpkgs.hostPlatform = "x86_64-linux";

  # cores, disk and mem:
  virtualisation = {
    cores = 42;
    memorySize = 40 * 1024;
    diskSize = 20 * 1024;
  };
  # Network settings:
  virtualisation.qemu.networkingOptions = [
    "-nic bridge,br=vmbr0,model=virtio-net-pci,mac=BC:24:11:1D:0E:19,helper=/run/wrappers/bin/qemu-bridge-helper"
    #"-nic bridge,br=vmbr4,mac=BC:24:11:1D:0E:A9,model=virtio-net-pci"
  ];
  networking.interfaces.eth1.useDHCP = false;
  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist/game-servers" = /persist/game-servers;
      # gives errors like:
      # Error: removing container efad71... from database: removing container efad... config from database: database disk image is malformed
      #"/var/lib/containers/storage" = /var/lib/containers/storage;
      "/root/.ssh" = "/persist/gameservers/ssh-root";
      "/etc/ssh" = "/persist/gameservers/ssh-base-keys";
    };
  };

  system.stateVersion = "25.11";
  networking.hostName = "gameservers";

  boot.loader.grub.enable = false;
  boot.loader.systemd-boot.enable = true;

  boot.loader.efi = {
    canTouchEfiVariables = false;
    efiSysMountPoint = "/boot";
  };

  boot.kernelParams = [
    "console=ttyS0,115200n8"
    "console=tty0"
  ];

  systemd.services."serial-getty@ttyS0".enable = true;

  services.openssh.enable = true;

  users.users.deadbeef = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBKIjWf+YcfijNBH+ilujFPNpgVZH9jD1PA1GiIzIWxO deadbeef@l-x13s"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgBgeVe/DSMZQAY8iS1D5Db3IbyteDSW+l79ZFD8Rmg deadbeef@l-esp"
    ];
    initialPassword = "";
  };

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
