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
  mkBridgeTrunk =
    import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-bridge-trunk-networkd.nix"
      {
        inherit lib pkgs;
      };
in
{
  imports = [
    # FYI, check:
    # ../s-router-core/host-config/network.nix


    # it's the eth2, because this is an overwrite...
    (mkBridgeTrunk "eth2" { bridge = "br-lan-trunk"; })
    #(mkBridgeTrunk "eth1" { bridge = "br-wan-trunk"; })
  ];

  #containers = lib.mkMerge [
  #  {
  #    "${config.networking.hostName}-container".bindMounts."/run/secrets" = {
  #      hostPath = "/run/secrets";
  #    };
  #  }
  #];

  #sops.secrets.subnet-ipv6 = { };
}
