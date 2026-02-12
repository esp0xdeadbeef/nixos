# FILE: ./s-router-core/container-settings.nix
{
  config,
  lib,
  outPath,
  ...
}:

let
  fabric = import "${outPath}/library/100-fabric-routing/inputs";
  upstreamVlans = fabric.upstreamVlans or [ 4 5 ];

  lanBridge = "br-lan-trunk";

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

        # Unique guest interface name per container
        extraVeths = {
          "${guestIf}" = {
            hostBridge = lanBridge;
          };
        };

        specialArgs = {
          inherit outPath;
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
  containers = lib.listToAttrs (map mkContainer upstreamVlans);
}

