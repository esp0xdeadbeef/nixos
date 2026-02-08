{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  topo = import "${outPath}/library/100-fabric-routing/lib/topology.nix";
  nodeName = "s-router-policy-only";

  mkLinks = import "${outPath}/library/100-fabric-routing/lib/mk-links-from-topo.nix" {
    inherit lib;
  };
  mkL3 = import "${outPath}/library/100-fabric-routing/lib/mk-l3-from-topo.nix" { inherit lib pkgs; };
in
{
  imports = [
    (mkLinks nodeName topo)
    (mkL3 nodeName topo)
  ];
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = false;
  system.stateVersion = "25.11";

}
