{ profiles, ... }:
{
  imports = [
    profiles.nixos.nixos-shell-host.common

    ./vm-settings.nix
    ./restart-container.nix
    ./network.nix
    ./ssh.nix
    ./impermanence.nix
    ./persist-state-disk.nix
  ];
}
