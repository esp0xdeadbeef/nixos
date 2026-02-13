# ./s-router-core/container-settings.nix
{
  config,
  lib,
  fabricInputs,
  ...
}:

let
  # For "core VPN containers per tenant", use tenantVlans (10..80)
  tenantVlans = fabricInputs.tenantVlans;

  policyBase = fabricInputs.policyAccessTransitBase or 100;
  transitVidFor = vid: policyBase + vid;
  transitBridgeFor = vid: "tr${toString (transitVidFor vid)}";

  mkContainer =
    vid:
    let
      name = "s-router-core-vpn-${toString vid}";
      guestIf = "uplink-${toString vid}";
    in
    {
      inherit name;
      value = {
        autoStart = true;
        privateNetwork = true;

        extraVeths = {
          "${guestIf}" = {
            # IMPORTANT: attach to transit bridge, not tenant LAN bridge
            hostBridge = transitBridgeFor vid;
          };
        };

        specialArgs = {
          vid = vid;
          guestIf = guestIf;
        };

        config = ./container;

        additionalCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
      };
    };

in
{
  containers = lib.listToAttrs (map mkContainer tenantVlans);
}

