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
    "-nic bridge,br=vmbr0,mac=BA:24:11:8D:19:5D,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,mac=BC:24:11:1D:1E:B9,model=virtio-net-pci"
  ];
  
  #services.openssh.permitRootLogin = lib.mkForce "yes";
 
  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/persist" = "/persist/vm-persists/${config.networking.hostName}";
      "/var/lib/containers/storage" = /var/lib/containers/storage;
    };
  };

  system.stateVersion = "25.11";
  

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
