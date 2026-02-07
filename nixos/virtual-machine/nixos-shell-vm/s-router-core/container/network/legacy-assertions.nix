{ lib, config, ... }:

let
  legacyBridge = "br-vlan1010";
  legacyAddr = "10.255.255.1/29";

  networks = config.systemd.network.networks or { };
  netdevs = config.systemd.network.netdevs or { };

  bridgeExists = lib.any (n: (netdevs.${n}.netdevConfig.Name or null) == legacyBridge) (
    lib.attrNames netdevs
  );

  addrExists = lib.any (
    n:
    let
      addrs = networks.${n}.addresses or [ ];
    in
    lib.any (a: a.Address == legacyAddr) addrs
  ) (lib.attrNames networks);
in
{
  assertions = [
    {
      assertion = bridgeExists;
      message =
        "LEGACY ASSERTION FAILED: bridge ${legacyBridge} is missing. "
        + "Legacy IPv4 /29 must remain untouched.";
    }

    {
      assertion = addrExists;
      message =
        "LEGACY ASSERTION FAILED: address ${legacyAddr} is not assigned. "
        + "Kea DHCPv4 on legacy VLAN would break.";
    }
  ];
}
