{ pkgs, self, ... }:
{
  imports = [
    ./eno1-router-vms.nix
    ./servers.nix
  ];
}
