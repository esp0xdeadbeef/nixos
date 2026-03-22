{
  config,
  lib,
  vlanId,
  transitVlanId ? (policyAccessTransitBase + vlanId),
  policyAccessTransitBase,
  outPath,
  fabricNodeContext,
  ...
}:

let
  splitCIDR =
    cidr:
      let
        parts = lib.splitString "/" cidr;
      in
      if builtins.length parts == 2 then
        {
          address = builtins.elemAt parts 0;
          prefix = builtins.elemAt parts 1;
        }
      else
        throw ''
          networkd-from-topology:

          Invalid CIDR '${cidr}'.
        '';

  firstIPv4InSubnet =
    cidr:
      let
        ip = (splitCIDR cidr).address;
        octets = lib.splitString "." ip;
        prefix = (splitCIDR cidr).prefix;
      in
      if builtins.length octets == 4 then
        "${builtins.elemAt octets 0}.${builtins.elemAt octets 1}.${builtins.elemAt octets 2}.1/${prefix}"
      else
        throw ''
          networkd-from-topology:

          Cannot derive router IPv4 from subnet '${cidr}'.
        '';

  firstIPv6InSubnet =
    cidr:
      let
        base = (splitCIDR cidr).address;
        prefix = (splitCIDR cidr).prefix;
        addr =
          if lib.hasSuffix "::" base then
            "${base}1"
          else
            "${base}::1";
      in
      "${addr}/${prefix}";

  defaultVia4FromRoutes =
    routes:
      let
        defaults =
          builtins.filter (r: (r.dst or null) == "0.0.0.0/0" && r ? via4) routes;
      in
      if defaults != [ ] then
        (builtins.head defaults).via4
      else
        throw ''
          networkd-from-topology:

          No IPv4 default route found in transit interface routes.
        '';

  defaultVia6FromRoutes =
    routes:
      let
        defaults =
          builtins.filter (
            r:
              (
                (r.dst or null) == "::/0"
                || (r.dst or null) == "0000:0000:0000:0000:0000:0000:0000:0000/0"
              )
              && r ? via6
          ) routes;
      in
      if defaults != [ ] then
        (builtins.head defaults).via6
      else
        throw ''
          networkd-from-topology:

          No IPv6 default route found in transit interface routes.
        '';

  tenantNetworks =
    if fabricNodeContext ? networks && builtins.isAttrs fabricNodeContext.networks then
      fabricNodeContext.networks
    else
      { };

  tenantNetworkNames =
    builtins.filter (n: n != "loopback") (builtins.attrNames tenantNetworks);

  tenantNetwork =
    if builtins.length tenantNetworkNames == 1 then
      tenantNetworks.${builtins.head tenantNetworkNames}
    else
      throw ''
        networkd-from-topology:

        Expected exactly 1 tenant network for access node.

        Found:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ tenantNetworkNames)}
      '';

  interfaces =
    if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
      fabricNodeContext.interfaces
    else
      { };

  interfaceNames = builtins.attrNames interfaces;

  transitIfName =
    let
      matches =
        builtins.filter (
          ifName:
            let
              iface = interfaces.${ifName};
            in
            builtins.isAttrs iface
            && (iface.kind or null) == "p2p"
        ) interfaceNames;
    in
    if builtins.length matches == 1 then
      builtins.head matches
    else
      throw ''
        networkd-from-topology:

        Expected exactly 1 p2p transit interface.

        Found:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ matches)}
      '';

  transitIf = interfaces.${transitIfName};

  tenantVlan = vlanId;
  transitVlan = transitVlanId;

  lanAddr4 = firstIPv4InSubnet tenantNetwork.ipv4;
  lanAddr6 = firstIPv6InSubnet tenantNetwork.ipv6;

  trAddr4 = transitIf.addr4;
  trAddr6 = transitIf.addr6;

  trGw4 = defaultVia4FromRoutes (transitIf.routes.ipv4 or [ ]);
  trGw6 = defaultVia6FromRoutes (transitIf.routes.ipv6 or [ ]);
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.networks = {
    "10-lan" = {
      matchConfig.Name = "lan-${toString tenantVlan}";

      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = true;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses = [
        { Address = lanAddr4; }
        { Address = lanAddr6; }
      ];
    };

    "20-transit" = {
      matchConfig.Name = "tr-${toString transitVlan}";

      networkConfig = {
        DHCP = "no";
        IPv4Forwarding = true;
        IPv6Forwarding = true;
        IPv6AcceptRA = false;
        ConfigureWithoutCarrier = true;
      };

      linkConfig.RequiredForOnline = false;

      addresses = [
        { Address = trAddr4; }
        { Address = trAddr6; }
      ];

      routes = [
        {
          Destination = "0.0.0.0/0";
          Gateway = trGw4;
        }
        {
          Destination = "::/0";
          Gateway = trGw6;
        }
      ];
    };
  };
}
