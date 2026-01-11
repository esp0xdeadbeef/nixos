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
      "/var/lib/unifi" = "/persist/infra/unifi";
      "/root/.ssh" = "/persist/infra/ssh-root";
      "/etc/ssh" = "/persist/infra/ssh-base-keys";
    };
  };

  system.stateVersion = "25.11";

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
