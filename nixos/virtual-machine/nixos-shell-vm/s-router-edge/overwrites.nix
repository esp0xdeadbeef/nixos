{
  outPath,
  lib,
  pkgs,
  ...
}:
let
  mkBridgeTrunk =
    import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-trunk-networkd.nix"
      {
        inherit lib pkgs;
      };
in
{
  imports = [
    (mkBridgeTrunk "eth1" { bridge = "br-lan-trunk"; })
  ];
}
