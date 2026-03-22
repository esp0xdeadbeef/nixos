{
  lib,
  fabricNodeContext,
  fabricSpec,
  ...
}:

let
  port =
    if fabricSpec ? ports && fabricSpec.ports ? policy then
      fabricSpec.ports.policy
    else
      throw "missing fabricSpec.ports.policy";

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
  systemd.network.networks."20-policy" = {
    matchConfig.Name = "policy";

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
