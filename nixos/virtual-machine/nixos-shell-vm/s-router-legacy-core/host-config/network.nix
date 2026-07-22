{ relativeRepo
, lib
, pkgs
, ...
}:

let
  mkMgmt = import (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix") {
    inherit lib pkgs;
  };
  mkBridge = import (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix") {
    inherit lib pkgs;
  };
  mkBridgeTrunk =
    import (relativeRepo.module "library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-trunk-networkd.nix")
      {
        inherit lib pkgs;
      };
in
{
  imports = [
    (mkMgmt "eth0" 2 { bridge = "vlan2"; })
    (mkBridgeTrunk "eth0" { bridge = "br-lan-trunk"; })
    (mkBridgeTrunk "eth1" { bridge = "br-wan-trunk"; })

    #(mkBridge "eth0" 3 { bridge = "vlan3"; })
    #(mkBridge "eth0" 4 { bridge = "vlan4"; })
    #(mkBridge "eth0" 5 { bridge = "vlan5"; })
    #(mkBridge "eth0" 6 { bridge = "vlan6"; })
    #(mkBridge "eth0" 7 { bridge = "vlan7"; })
    #(mkBridge "eth0" 8 { bridge = "vlan8"; })
    #(mkBridge "eth0" 9 { bridge = "vlan9"; })
    #(mkBridge "eth0" 1010 { bridge = "vlan1010"; })
  ];

}
