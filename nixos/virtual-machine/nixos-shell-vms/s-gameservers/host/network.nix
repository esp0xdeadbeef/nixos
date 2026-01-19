{ lib, pkgs, ... }:

let
  mkMgmt = import ../../1-helpers/mk-management-networkd.nix { inherit lib pkgs; };
  mkBridge = import ../../1-helpers/mk-bridge-networkd.nix { inherit lib pkgs; };
in
{
  imports = [
    (mkMgmt "eth0" 2 { bridge = "vlan2"; })
    #(mkBridge "eth0" 2 { bridge = "vlan2"; })
    (mkBridge "eth0" 7 { bridge = "vlan7"; })
    (mkBridge "eth0" 6 { bridge = "vlan6"; })
  ];

}
