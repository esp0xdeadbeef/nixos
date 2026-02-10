# default.nix — s-router-policy-only (debug-style wiring)
{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  nodeName = "s-router-policy-only";

  # === Addressing inputs (EXPLICIT, SAME AS DEBUG) ===
  ulaPrefix = "fd42:dead:beef";
  tenantV4Base = "10.10";

  # === Topology pipeline (IDENTICAL to debug) ===
  raw =
    import "${outPath}/library/100-fabric-routing/lib/topology-gen.nix"
      {
        inherit lib;
      }
      {
        tenantVlans = [
          10
          20
          30
          40
          50
          60
          70
          80
        ];
        policyAccessTransitBase = 100;
        corePolicyTransitVlan = 200;
      };

  resolved = import "${outPath}/library/100-fabric-routing/lib/topology-resolve.nix" {
    inherit lib ulaPrefix tenantV4Base;
  } raw;

  routed = import "${outPath}/library/100-fabric-routing/lib/routing-gen.nix" {
    inherit lib ulaPrefix tenantV4Base;
  } resolved;

  # === Renderers (now receive full context) ===
  mkLinks = import "${outPath}/library/100-fabric-routing/lib/mk-links-from-topo.nix" {
    inherit lib;
  };

  mkL3 = import "${outPath}/library/100-fabric-routing/lib/mk-l3-from-topo.nix" {
    inherit
      lib
      pkgs
      ulaPrefix
      tenantV4Base
      ;
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
