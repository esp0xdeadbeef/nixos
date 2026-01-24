{ pkgs, ... }:
{
  imports = [
    ./firewall.nix
    ./nat-lxc.nix
    ./nmcli.nix
  ];
}
