# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/container-router-access/container-settings.nix
# ./container-router-access/container-settings.nix
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
          # unique downlink bridge per tenant LAN
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

              # NEW STYLE: services driven by vlanId + fabric inputs
              ./kea.nix
              ./kea-services.nix
              ./dns.nix
              ./radvd.nix

              ../debugging-packages.nix
            ];

            boot.isContainer = true;
            system.stateVersion = "25.11";

            networking.hostName = name;
            networking.useHostResolvConf = false;

            # keep it explicit; policy lives elsewhere
            networking.firewall.enable = false;
            services.resolved.enable = false;
          };

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_SYS_ADMIN"
          "CAP_NET_BIND_SERVICE"
          "CAP_NET_RAW"
        ];
      };
    };

in
{
  containers = lib.listToAttrs (map mkContainer tenantVlans);
}
