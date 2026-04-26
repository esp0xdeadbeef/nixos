{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # cache indexes with this command:
    nix-index
    # needed to format nix configs:
    nixfmt
    # to hack your own packages
    nix-prefetch
    # this is available a different way ( google it) but not required because we push via nixos rebuilds:
    #home-manager
  ];
}
