{ lib
, config
, pkgs
, ...
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
    # NIC MACs are identity-bearing and live in secrets/s-router-vpn-egress.yaml
    # (vmbr0-mac, vmbr4-mac). QEMU auto-generates at launch; if the pinned
    # identities are required again, read the secret and pass mac=<value> here
    # through a launch wrapper.
    "-nic bridge,br=vmbr0,model=virtio-net-pci"
    "-nic bridge,br=vmbr4,model=virtio-net-pci"
  ];

  #services.openssh.permitRootLogin = lib.mkForce "yes";

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
