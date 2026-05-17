{
  builders,
  lib,
  siteName ? "nixos",
  clientTenant ? "client",
  clientCount ? 2,
}:

let
  rangeFromOne = count: map (index: index + 1) (lib.range 0 (count - 1));

  twoDigit = index:
    if index < 10 then
      "0${toString index}"
    else
      toString index;

  clientName = index: "${siteName}-${clientTenant}${twoDigit index}";

  mkDynamicClient =
    name: bridge:
    {
      autoStart = true;
      privateNetwork = true;
      hostBridge = bridge;
      config = builders.mkDhcpEndpoint {
        hostname = name;
        dnsServers = [ ];
      };
    };

  mkNumberedClients =
    bridge:
    builtins.listToAttrs (
      map
        (index: {
          name = clientName index;
          value = mkDynamicClient (clientName index) bridge;
        })
        (rangeFromOne clientCount)
    );
in
{
  nixos-admin-test = mkDynamicClient "nixos-admin-test" "admin";
  nixos-mgmt-test = mkDynamicClient "nixos-mgmt-test" "mgmt";
  nixos-streaming-test = mkDynamicClient "nixos-streaming-test" "streaming";
} // mkNumberedClients "client"
