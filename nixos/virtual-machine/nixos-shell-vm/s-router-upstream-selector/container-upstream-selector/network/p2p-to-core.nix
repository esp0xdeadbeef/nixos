{
  lib,
  fabricNodeContext,
  ...
}:

let
  ifName = "upstream-core";

  ifaces =
    if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
      fabricNodeContext.interfaces
    else
      throw ''
        container: fabricNodeContext missing `interfaces` attrset

        fabricNodeContext:
        ${builtins.toJSON fabricNodeContext}
      '';

  candidates = lib.filterAttrs (
    _: v:
    builtins.isAttrs v
    && (v.kind or null) == "p2p"
    && (v.carrier or null) == "lan"
    && (
      let
        linkName = v.link or "";
      in
      lib.hasInfix "s-router-core-" linkName
    )
  ) ifaces;

  names = builtins.attrNames candidates;

  _one =
    if builtins.length names == 1 then
      true
    else
      throw ''
        container: expected exactly 1 core-facing p2p interface

        found: ${toString (builtins.length names)}

        candidates:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ names)}

        all interfaces:
        ${builtins.concatStringsSep "\n  - " ([ "" ] ++ builtins.attrNames ifaces)}
      '';

  ifaceName = builtins.head names;
  iface = candidates.${ifaceName};

  addr4 =
    if iface ? addr4 && iface.addr4 != null then
      iface.addr4
    else
      throw ''
        container: p2p iface '${ifaceName}' missing addr4

        iface:
        ${builtins.toJSON iface}
      '';

  addr6 =
    if iface ? addr6 && iface.addr6 != null then
      iface.addr6
    else
      throw ''
        container: p2p iface '${ifaceName}' missing addr6

        iface:
        ${builtins.toJSON iface}
      '';

  routeList4 =
    if iface ? routes && iface.routes ? ipv4 && builtins.isList iface.routes.ipv4 then
      iface.routes.ipv4
    else
      [ ];

  routeList6 =
    if iface ? routes && iface.routes ? ipv6 && builtins.isList iface.routes.ipv6 then
      iface.routes.ipv6
    else
      [ ];

  mkRoute =
    r:
    lib.filterAttrs (_: v: v != null) {
      Destination = r.dst or null;
      Gateway =
        if r ? via4 && r.via4 != null then
          r.via4
        else if r ? via6 && r.via6 != null then
          r.via6
        else
          null;
    };

  routes =
    map mkRoute (lib.filter (r: r ? via4 && r.via4 != null) routeList4)
    ++ map mkRoute (lib.filter (r: r ? via6 && r.via6 != null) routeList6);

in
{
  systemd.network.networks."10-${ifName}" = {
    matchConfig.Name = ifName;

    addresses = [
      { Address = addr4; }
      { Address = addr6; }
    ];

    routes = routes;

    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };
  };
}
