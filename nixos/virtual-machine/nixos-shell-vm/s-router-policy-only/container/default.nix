{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  nodeName = "s-router-policy-only";

  fabricInputs = import "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  ulaPrefix = "fd42:dead:beef";
  tenantV4Base = "10.10";

  raw =
    import "${outPath}/library/100-fabric-routing/lib/topology-gen.nix"
      { inherit lib; }
      {
        tenantVlans = fabricInputs.tenantVlans or [ 10 20 30 40 50 60 70 80 ];
        policyAccessTransitBase = fabricInputs.policyAccessTransitBase or 100;
        corePolicyTransitVlan = fabricInputs.corePolicyTransitVlan or 200;
      };

  resolved0 = import "${outPath}/library/100-fabric-routing/lib/topology-resolve.nix" {
    inherit lib ulaPrefix tenantV4Base;
  } raw;

  resolved =
    resolved0
    // {
      wans = lib.filter (w: (w.iface or "") != "lan1010") (resolved0.wans or [ ]);
      lans = lib.filter (l: (l.iface or "") != "lan1010") (resolved0.lans or [ ]);
    };

  routed = import "${outPath}/library/100-fabric-routing/lib/routing-gen.nix" {
    inherit lib ulaPrefix tenantV4Base;
  } resolved;

  mkLinks = import "${outPath}/library/100-fabric-routing/lib/mk-links-from-topo.nix" {
    inherit lib;
  };

  mkL3 = import "${outPath}/library/100-fabric-routing/lib/mk-l3-from-topo.nix" {
    inherit lib pkgs ulaPrefix tenantV4Base;
  };

in
{
  imports = [
    (mkLinks nodeName routed)
    (mkL3 nodeName routed)
    ./debugging-packages.nix
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.networkmanager.enable = false;
  networking.useHostResolvConf = false;

  system.stateVersion = "25.11";
}
