{ lib }:

{
  names,
  routes,
  parentIf,
}:

{
  all,
  nodeName,
  linkName,
  iface,
}:

let
  needsBridge = iface.kind == "lan";
  carrier = iface.carrier or "lan";
  vlanId = iface.vlanId;

  parent = parentIf all nodeName carrier;

  vname = names.mkIfName {
    prefix = "v";
    hint = "${toString vlanId}-${linkName}";
    seed = "${nodeName}|${linkName}|${toString vlanId}";
  };

  bname = names.mkIfName {
    prefix = "br";
    hint = "-${linkName}";
    seed = "br|${nodeName}|${linkName}|${toString vlanId}";
  };

  networkOn = if needsBridge then bname else vname;

  routeSections = map routes.mkRouteSection ((iface.routes4 or [ ]) ++ (iface.routes6 or [ ]));

in
{
  netdevs = {
    "20-${vname}.netdev" = {
      netdevConfig = {
        Name = vname;
        Kind = "vlan";
      };
      vlanConfig.Id = vlanId;
    };
  }
  // lib.optionalAttrs needsBridge {
    "20-${bname}.netdev" = {
      netdevConfig = {
        Name = bname;
        Kind = "bridge";
      };
    };
  };

  networks = {
    "10-${parent}.network" = {
      matchConfig.Name = parent;
      networkConfig.VLAN = vname;
    };

    "30-${networkOn}.network" = {
      matchConfig.Name = networkOn;
      networkConfig = {
        Address = lib.filter (x: x != null) [
          iface.addr4 or null
          iface.addr6 or null
        ];
        IPForward = "yes";
        IPv6AcceptRA = "no";
      };
      routes = routeSections;
    };
  }
  // lib.optionalAttrs needsBridge {
    "25-${vname}.network" = {
      matchConfig.Name = vname;
      networkConfig = {
        Bridge = bname;
        LinkLocalAddressing = "no";
      };
    };
  };
}
