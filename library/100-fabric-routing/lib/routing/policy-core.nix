# lib/routing/policy-core.nix
{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

topo:

let
  links = topo.links or { };

  policyNode = "s-router-policy-only";
  coreNode = "s-router-core-wan";

  stripCidr = s: if s == null then null else builtins.elemAt (lib.splitString "/" s) 0;

  tenant4Dst = vid: "${tenantV4Base}.${toString vid}.0/24";
  tenant6DstUla = vid: "${ulaPrefix}:${toString vid}::/64";

  getEp = l: n: (l.endpoints or { }).${n} or { };
  setEp =
    l: n: ep:
    l
    // {
      endpoints = (l.endpoints or { }) // {
        "${n}" = ep;
      };
    };

  getTenantVid =
    ep:
    if ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

  # Collect tenant VLAN IDs from policy-access links
  tenantVids = lib.unique (
    lib.filter (x: x != null) (
      lib.concatMap (
        l:
        if l.kind == "p2p" && lib.hasPrefix "policy-access-" (l.name or "") then
          let
            # access node is the non-policy member
            ms = l.members or [ ];
            accessNode = if lib.head ms == policyNode then builtins.elemAt ms 1 else lib.head ms;
            epA = getEp l accessNode;
          in
          [ (getTenantVid epA) ]
        else
          [ ]
      ) (lib.attrValues links)
    )
  );

  # For each tenant, if access-tenant-<vid> has addr6Public, route that /64 too.
  tenantGuaPrefixes = lib.concatMap (
    vid:
    let
      lname = "access-tenant-${toString vid}";
      l = links.${lname} or null;
      ep =
        if l == null then
          null
        else
          let
            node = lib.head (l.members or [ ]);
          in
          (l.endpoints or { }).${node} or null;
    in
    if ep != null && ep ? addr6Public then
      let
        ip = stripCidr ep.addr6Public;
      in
      if ip != null && lib.hasSuffix "::1" ip then
        [ "${builtins.replaceStrings [ "::1" ] [ "::" ] ip}/64" ]
      else
        [ "${ip}/64" ]
    else
      [ ]
  ) tenantVids;

in
topo
// {
  links = lib.mapAttrs (
    _: l:
    if
      l.kind == "p2p"
      && (l.name or "") == "policy-core"
      && lib.elem policyNode (l.members or [ ])
      && lib.elem coreNode (l.members or [ ])
    then
      let
        epPolicy = getEp l policyNode;
        epCore = getEp l coreNode;

        # gateways must be plain IPs
        gw4 = stripCidr epCore.addr4;
        gw6 = stripCidr epCore.addr6;

        via4toPolicy = stripCidr epPolicy.addr4;
        via6toPolicy = stripCidr epPolicy.addr6;

        policyDefaults4 = [
          {
            dst = "0.0.0.0/0";
            via4 = gw4;
          }
        ];

        policyDefaults6 = [
          {
            dst = "::/0";
            via6 = gw6;
          }
        ];

        coreRoutes4 = map (vid: {
          dst = tenant4Dst vid;
          via4 = via4toPolicy;
        }) tenantVids;

        coreRoutes6 =
          (map (vid: {
            dst = tenant6DstUla vid;
            via6 = via6toPolicy;
          }) tenantVids)
          ++ (map (pfx: {
            dst = pfx;
            via6 = via6toPolicy;
          }) tenantGuaPrefixes);

      in
      setEp
        (setEp l policyNode (
          epPolicy
          // {
            routes4 = (epPolicy.routes4 or [ ]) ++ policyDefaults4;
            routes6 = (epPolicy.routes6 or [ ]) ++ policyDefaults6;
          }
        ))
        coreNode
        (
          epCore
          // {
            routes4 = (epCore.routes4 or [ ]) ++ coreRoutes4;
            routes6 = (epCore.routes6 or [ ]) ++ coreRoutes6;
          }
        )
    else
      l
  ) links;
}
