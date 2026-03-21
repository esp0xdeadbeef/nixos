{
  outPath,
  lib,
  pkgs,
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

    (mkBridge "eth0" 5 { bridge = "br-upstream"; })

    (mkBridge "eth0" 200 { bridge = "br-fabric"; })
  ];
}
