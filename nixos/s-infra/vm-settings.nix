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

  virtualisation.qemu.networkingOptions = lib.mkForce [
    "-nic none" # disable NAT.
    "-nic bridge,br=vmbr4,mac=BC:24:11:1D:0E:B9,model=virtio-net-pci"
  ];
  
  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/var/lib/containers/storage" = /var/lib/containers/storage;
      #"/persist/infra/unifi" = /usr/lib/unifi/data;

    "/var/lib/unifi" = "/persist/infra/unifi";
    };
  };

  system.stateVersion = "25.11";
  networking.hostName = "s-infra";

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
