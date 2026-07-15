{ profiles, ... }:
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.llm-clients.cache
    profiles.nixos.network.nebula-mesh

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
  ];

  system.stateVersion = "25.11";
}
