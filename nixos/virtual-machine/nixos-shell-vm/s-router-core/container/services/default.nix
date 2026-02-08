{ pkgs, ... }:
{
  imports = [
    ./kea-dhcp6.nix
    ./firewall.nix
    ./kea-v4.nix
  ];
}
