{ builders }:

let
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
in
{
  admin-test = mkDynamicClient "admin-test" "admin";
  client-test = mkDynamicClient "client-test" "client";
  client2-test = mkDynamicClient "client2-test" "client2";
  mgmt-test = mkDynamicClient "mgmt-test" "mgmt";
}
