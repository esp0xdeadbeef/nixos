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
in
{
  imports = [
    (mkBridge "eth0" 10 { bridge = "vlan10"; })
    (mkBridge "eth0" 20 { bridge = "vlan20"; })
    (mkBridge "eth0" 30 { bridge = "vlan30"; })
    (mkBridge "eth0" 40 { bridge = "vlan40"; })
    (mkBridge "eth0" 50 { bridge = "vlan50"; })
    (mkBridge "eth0" 60 { bridge = "vlan60"; })
    (mkBridge "eth0" 70 { bridge = "vlan70"; })
    (mkBridge "eth0" 80 { bridge = "vlan80"; })
    (mkBridge "eth0" 90 { bridge = "vlan90"; })
    (mkBridge "eth0" 100 { bridge = "vlan100"; })

  ];

}
