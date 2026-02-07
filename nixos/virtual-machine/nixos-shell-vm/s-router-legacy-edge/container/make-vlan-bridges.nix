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
    # old config vlans:
    (mkBridge "lan" 2 { bridge = "lan2"; })
    (mkBridge "lan" 7 { bridge = "lan7"; })
    (mkBridge "lan" 1010 { bridge = "lan1010"; })
  ];
}
