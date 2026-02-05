{ pkgs, lib }:
args@{ ... }:
{ config, ... }:

{
  _module.args = {
    inherit args;
  };

  imports = [
    ./networkd.nix
    ./nftables.nix
    ./kea.nix
    ./kea-services.nix
    ./radvd.nix
    ./dns.nix
  ];
}
