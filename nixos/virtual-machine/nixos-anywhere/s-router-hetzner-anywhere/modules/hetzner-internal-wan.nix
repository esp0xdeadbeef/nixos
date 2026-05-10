{ lib
, inventory
, hostName
, coreNodeName ? "c-router-core"
, uplinkName ? "wan"
}:
let
  deploymentHosts = ((inventory.deployment or { }).hosts or { });
  realizationNodes = ((inventory.realization or { }).nodes or { });
  host = deploymentHosts.${hostName} or (throw "missing deployment host ${hostName}");
  uplink = (host.uplinks or { }).${uplinkName} or (throw "missing ${hostName} uplink ${uplinkName}");
  coreNodes =
    lib.filterAttrs
      (_: node: (node.host or "") == hostName && ((node.logicalNode or { }).name or "") == coreNodeName)
      realizationNodes;
  coreNode =
    if coreNodes == { } then
      throw "missing ${coreNodeName} realization node on ${hostName}"
    else
      builtins.head (builtins.attrValues coreNodes);
  corePort = (coreNode.ports or { }).${uplinkName} or (throw "missing ${coreNodeName} port ${uplinkName}");
  coreInterface = corePort.interface or { };
  stripCidr = value: builtins.head (lib.splitString "/" value);
  isV6 = value: lib.hasInfix ":" value;
  firstOrThrow = message: values:
    if values == [ ] then throw message else builtins.head values;
  hostAddress4 =
    firstOrThrow "missing private IPv4 host address on ${hostName} ${uplinkName}"
      (builtins.filter (value: !(isV6 value)) (uplink.hostAddresses or [ ]));
  hostAddress6 =
    firstOrThrow "missing private IPv6 host address on ${hostName} ${uplinkName}"
      (builtins.filter isV6 (uplink.hostAddresses or [ ]));
  routeGateway = family: prefix:
    let
      routes = ((coreInterface.routes or { }).${family} or [ ]);
      matches = builtins.filter (route: (route.prefix or "") == prefix) routes;
    in
      (firstOrThrow "missing ${family} ${prefix} route on ${coreNodeName} ${uplinkName}" matches).via
        or (throw "missing ${family} gateway on ${coreNodeName} ${uplinkName}");
in
{
  inherit hostAddress4 hostAddress6;
  hostGateway4 = stripCidr hostAddress4;
  hostGateway6 = stripCidr hostAddress6;
  coreAddress4 = coreInterface.addr4 or (throw "missing ${coreNodeName} ${uplinkName} addr4");
  coreAddress6 = coreInterface.addr6 or (throw "missing ${coreNodeName} ${uplinkName} addr6");
  coreGateway4 = routeGateway "ipv4" "0.0.0.0/0";
  coreGateway6 = routeGateway "ipv6" "::/0";
  coreAddress4Bare = stripCidr (coreInterface.addr4 or "");
  coreAddress6Bare = stripCidr (coreInterface.addr6 or "");
}
