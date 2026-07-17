{ profiles, ... }:
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.server.no-sleep
    profiles.nixos.llm-clients.cache
    profiles.nixos.network.nebula-mesh

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
    ./github-token.nix
  ];

  system.stateVersion = "25.11";
}
