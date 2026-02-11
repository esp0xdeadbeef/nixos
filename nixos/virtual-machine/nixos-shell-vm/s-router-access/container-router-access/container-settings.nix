# ./container-router-access/container-settings.nix
# ./s-router-access/container-router-access/container-settings.nix
# FILE: s-router-access/container-router-access/container-settings.nix
{
  config,
  lib,
  outPath,
  ...
}:

let
  fabric = import "${outPath}/library/100-fabric-routing/inputs";
  tenantVlans = fabric.tenantVlans;
  policyBase = fabric.policyAccessTransitBase or 100;

  lanBridgeFor = vid: "br-lan-${toString vid}";

  mkContainer =
    vid:
    let
      name = "s-router-access-${toString vid}";
      transitVid = policyBase + vid;
    in
    {
      inherit name;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          # FIX: unique downlink bridge per tenant LAN
          "lan-${toString vid}".hostBridge = lanBridgeFor vid;

          # transit stays per-tenant
          "tr-${toString vid}".hostBridge = "tr${toString transitVid}";
        };

        specialArgs = {
          inherit outPath;
          vlanId = vid;
          policyAccessTransitBase = policyBase;
        };

        config =
          { ... }:
          {
            imports = [
              ./node-from-topology.nix
              ./networkd-from-topology.nix
              ../debugging-packages.nix
            ];

            boot.isContainer = true;
            system.stateVersion = "25.11";

            networking.hostName = name;
            networking.useHostResolvConf = false;
          };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_SYS_ADMIN"
        ];
      };
    };

in
{
  containers = lib.listToAttrs (map mkContainer tenantVlans);
}
