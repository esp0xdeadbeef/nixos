{
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    # Explicit, stable, flake-safe import of internal module
    (modulesPath + "/virtualisation/qemu-vm.nix")
    ./nixos-shell-servers
    ./tty.nix
  ];

  #fileSystems."/mnt/host" = {
  #  device = "hostshare";
  #  fsType = "virtiofs";
  #};
  # Basic VM tweak
  #virtualisation.writableStore = true;
  #virtualisation.mountHostNixStore = false;
  #virtualisation.useNixStoreImage = true;
  #virtualisation.writableStore = true;
  #virtualisation.writableStoreUseTmpfs = false;

  virtualisation.mountHostNixStore = true;
  #virtualisation.directBoot = true;
  virtualisation.sharedDirectories = {
    homefolder = {
      source = "/home/deadbeef/github/nixos";
      target = "/home/deadbeef/github/nixos";
    };
  };
  networking.firewall.enable = false;

  virtualisation.forwardPorts = [
    {
      from = "host";
      host.port = 2222;
      guest.port = 22;
    }
  ];
  virtualisation.qemu.options = [
    "-display"
    "none"
    "-serial"
    "mon:stdio"
  ];

  systemd.tmpfiles.rules = [
    "d /mnt 0755 root root - -"
    "d /mnt/host 0755 root root - -"
  ];
  fileSystems."/mnt/host" = {
    device = "hostshare";
    fsType = "9p";
    options = [
      "trans=virtio"
      "version=9p2000.L"
      "msize=1048576"
    ];
  };

  virtualisation.graphics = false;

  environment.systemPackages = [
    pkgs.btop
    pkgs.fastfetch
    pkgs.screen
  ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  virtualisation = {
    cores = 64;
    memorySize = 1024 * 16;
    #writableStoreUseTmpfs = false;
  };

  system.stateVersion = "25.11";
  virtualisation.diskSize = 20 * 1024;

}
