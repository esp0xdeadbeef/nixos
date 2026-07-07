{ profiles, ... }:
{
  imports = [
    profiles.nixos.server.dell-vm-host
    profiles.nixos.llm-clients.cache

    ./libvirt.nix
    ./nixos-shell-servers
    ./hardware
    ./connect-nas
  ];

  system.stateVersion = "25.11";
}
