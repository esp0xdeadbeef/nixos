{ pkgs, ... }:
{
  imports = [
    ./debug-packages.nix
    ./unifi.nix
    ./vm-settings.nix
    ./network.nix
    ./ssh.nix
    ./impermanence.nix
    ../../1-helpers/vm-storage-persist.nix
  ];
}
