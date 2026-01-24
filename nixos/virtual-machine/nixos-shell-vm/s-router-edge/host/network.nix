{
  lib,
  pkgs,
  outPath,
  ...
}:

let
  mkMgmt = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix" {
    inherit lib pkgs;
  };
  mkBridge = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-networkd.nix" {
    inherit lib pkgs;
  };
in
{
  imports = [
    (mkMgmt "eth0" 2 { bridge = "vlan2"; })
    (mkBridge "eth0" 3 { bridge = "vlan3"; })
    (mkBridge "eth0" 7 { bridge = "vlan7"; })
    (mkBridge "eth0" 1010 { bridge = "vlan1010"; })
  ];

}
