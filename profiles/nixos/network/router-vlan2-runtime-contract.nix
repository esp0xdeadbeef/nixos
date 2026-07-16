{ config
, lib
, name
, ...
}:
let
  network = config.systemd.network;
  netdevs = builtins.attrValues (network.netdevs or { });
  networks = builtins.attrValues (network.networks or { });
  networkEntries =
    map
      (networkName: {
        inherit networkName;
        value = network.networks.${networkName};
      })
      (builtins.attrNames (network.networks or { }));

  has = value: values: builtins.elem value values;
  atLeastOne = predicate: values: lib.any predicate values;
  firstNetwork = predicate: lib.findFirst (entry: predicate entry.value) null networkEntries;

  isDisabled = value: value == false || value == "no" || value == "false";
  isIpv4Dhcp = value: value == true || value == "yes" || value == "ipv4";

  vlanInterface = "eth0.2";
  vlanId = 2;
  bridge = "vlan2";

  vlanNetdev = netdev:
    (netdev.netdevConfig.Kind or null) == "vlan"
    && (netdev.netdevConfig.Name or null) == vlanInterface
    && (netdev.vlanConfig.Id or null) == vlanId;

  bridgeNetdev = netdev:
    (netdev.netdevConfig.Kind or null) == "bridge"
    && (netdev.netdevConfig.Name or null) == bridge;

  parentNetwork = networkConfig:
    (networkConfig.matchConfig.Name or null) == "eth0"
    && has vlanInterface (networkConfig.networkConfig.VLAN or [ ])
    && isDisabled (networkConfig.networkConfig.DHCP or "no");

  vlanNetwork = networkConfig:
    (networkConfig.matchConfig.Name or null) == vlanInterface
    && (networkConfig.networkConfig.Bridge or null) == bridge
    && isDisabled (networkConfig.networkConfig.DHCP or "no");

  effectiveBridgeNetwork =
    firstNetwork (networkConfig: (networkConfig.matchConfig.Name or null) == bridge);
  effectiveBridgeNetworkHasIpv4Dhcp =
    effectiveBridgeNetwork != null
    && isIpv4Dhcp (effectiveBridgeNetwork.value.networkConfig.DHCP or null);

  errors =
    lib.optionals (!atLeastOne vlanNetdev netdevs) [
      "${name}: runtime must define at least one VLAN netdev eth0.2 with vlanConfig.Id = 2"
    ]
    ++ lib.optionals (!atLeastOne bridgeNetdev netdevs) [
      "${name}: runtime must define at least one bridge netdev vlan2"
    ]
    ++ lib.optionals (!atLeastOne parentNetwork networks) [
      "${name}: runtime must define at least one eth0 network that attaches eth0.2 and disables DHCP"
    ]
    ++ lib.optionals (!atLeastOne vlanNetwork networks) [
      "${name}: runtime must define at least one eth0.2 network enslaved into vlan2 with DHCP disabled"
    ]
    ++ lib.optionals (!effectiveBridgeNetworkHasIpv4Dhcp) [
      "${name}: runtime first matching vlan2 network must use IPv4 DHCP with optional IPv6 SLAAC/RA client"
    ];
in
{
  assertions = [
    {
      assertion = errors == [ ];
      message = builtins.concatStringsSep "; " errors;
    }
  ];
}
