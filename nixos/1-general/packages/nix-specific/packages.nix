{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    nix-index
    nixfmt-rfc-style
    # this is available a different way ( google it) but not required because we push via nixos rebuilds:
    #home-manager
  ];
}
