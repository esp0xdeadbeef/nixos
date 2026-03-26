{
  lib,
  fabricNodeContext,
  containerName,
  ...
}:

let
  ifName = "${containerName}-fabric";

  ifaces =
    if fabricNodeContext ? interfaces && builtins.isAttrs fabricNodeContext.interfaces then
      fabricNodeContext.interfaces
    else if fabricNodeContext ? effectiveRuntimeRealization
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization
      && fabricNodeContext.effectiveRuntimeRealization ? interfaces
      && builtins.isAttrs fabricNodeContext.effectiveRuntimeRealization.interfaces
    then
      fabricNodeContext.effectiveRuntimeRealization.interfaces
    else
      throw ''
        container: fabricNodeContext missing `interfaces` attrset

        fabricNodeContext:
        ${builtins.toJSON fabricNodeContext}
      '';

  candidates =
    lib.filterAttrs (
      _: v:
      builtins.isAttrs v
      && (
        (v.kind or null) == "p2p"
        || (v.sourceKind or null) == "p2p"
      )
    ) ifaces;

  names = builtins.attrNames candidates;

  _one =
    if builtins.length names == 1 then
      true
    else
      throw ''
        container: expected exactly 1 p2p interface for core role

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
in
{
  systemd.network.networks."20-${ifName}" = {
    matchConfig.Name = ifName;

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
