{
  lib,
  fabricNodeContext,
  fabricSpec,
  ...
}:

let
  port =
    if fabricSpec ? ports && fabricSpec.ports ? core then
      fabricSpec.ports.core
    else
      throw "missing fabricSpec.ports.core";

  linkName =
    if port ? link then port.link else throw "missing link";

  ifaces =
    if fabricNodeContext ? interfaces then
      fabricNodeContext.interfaces
    else
      throw "missing interfaces";

  iface =
    if builtins.hasAttr linkName ifaces then
      ifaces.${linkName}
    else
      throw "link not found";

  addr4 = iface.addr4 or (throw "missing addr4");
  addr6 = iface.addr6 or (throw "missing addr6");

in
{
  systemd.network.networks."10-core" = {
    matchConfig.Name = "core";

    addresses = [
      { Address = addr4; }
      { Address = addr6; }
    ];

    networkConfig = {
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };
  };
}
