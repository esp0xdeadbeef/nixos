{ pkgs, ... }:
{
  imports = [
    ./firewall.nix
    ./kea-v4.nix
  ];
}
