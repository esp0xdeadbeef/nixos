{
  pkgs,
  lib,
  config,
  outPath,
  ...
}:

let
  getAttrs = import "${outPath}/library/100-fabric-routing/lib/get-attrs.nix" { inherit lib; };

  attrs = getAttrs {
    lans = [ 10 ];
    wans = [ 1010 ];

    # 🔥 FIX: transit MUST match core (VLAN 100)
    transits = [
      {
        vlanId = 100;
        node = "edge";
      }
    ];
  };

  mk-nixos-vlan = import ./mk-nixos-vlan { inherit pkgs lib; };

  vlanModule = mk-nixos-vlan {
    inherit (attrs)
      lans
      wans
      transits
      domain
      ;
  };

in
{
  imports = [
    ./debugging-packages.nix
    vlanModule
    ./make-vlan-bridges.nix
    ./nftables.nix
  ];

  services.resolved.enable = false;
  networking.useHostResolvConf = false;

  system.stateVersion = "25.11";
  boot.isContainer = true;
  networking.firewall.enable = false;
}
