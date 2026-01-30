{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./networking.nix
    #./container-settings.nix
    ./unifi.nix
    ./ipref3.nix
    ./dns.nix
  ];
  system.stateVersion = "25.11";
}
