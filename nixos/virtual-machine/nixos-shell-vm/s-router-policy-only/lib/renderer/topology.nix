{
  lib,
  hostname,
  runtimeTarget,
  runtimePorts,
}:

let
  mkRoute =
    route:
    {
      Destination = route.dst;
    }
    // lib.optionalAttrs (route ? via4) { Gateway = route.via4; }
    // lib.optionalAttrs (route ? via6) { Gateway = route.via6; };
in
runtimeIfName: runtimeIf:
let
  linkName =
    if runtimeIf ? link then
      runtimeIf.link
    else
      abort ''
        renderer/lib/renderer/topology.nix
        hostname: ${hostname}
        runtimeIfName: ${runtimeIfName}
        linkName: n/a
        error: runtime interface link missing
      '';

  portMatches = lib.filter (port: (port.link or null) == linkName) runtimePorts;

  runtimePort =
    if builtins.length portMatches == 1 then
      builtins.elemAt portMatches 0
    else if builtins.length portMatches == 0 then
      abort ''
        renderer/lib/renderer/topology.nix
        hostname: ${hostname}
        runtimeIfName: ${runtimeIfName}
        linkName: ${linkName}
        error: runtime interface link not covered by runtime port
      ''
    else
      abort ''
        renderer/lib/renderer/topology.nix
        hostname: ${hostname}
        runtimeIfName: ${runtimeIfName}
        linkName: ${linkName}
        error: runtime interface link covered by multiple runtime ports
      '';

  renderedIfName =
    if runtimeIf ? interface then
      runtimeIf.interface
    else if runtimeIf ? name then
      runtimeIf.name
    else
      runtimeIfName;

  addresses =
    (lib.optional (runtimeIf ? addr4) { Address = runtimeIf.addr4; })
    ++ (lib.optional (runtimeIf ? addr6) { Address = runtimeIf.addr6; });

  routes =
    map mkRoute (
      (runtimeIf.routes.ipv4 or [ ])
      ++ (runtimeIf.routes.ipv6 or [ ])
    );
in
{
  inherit
    runtimeIfName
    renderedIfName
    linkName
    runtimePort
    addresses
    routes
    ;

  runtimeIf = runtimeIf;
}
