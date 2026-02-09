# lib/routing/policy-access.nix
{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

topo:

let
  links = topo.links or { };
  policyNode = "s-router-policy-only";

  isPolicyAccess =
    lname: l:
    l.kind == "p2p" && lib.hasPrefix "policy-access-" lname && lib.elem policyNode (l.members or [ ]);

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

  # Find the "access-tenant-<vid>" LAN link for an access node, and return its endpoint.
  tenantLanEpFor =
    accessNode: vid:
    let
      lname = "access-tenant-${toString vid}";
      l = links.${lname} or null;
    in
    if l == null then null else (l.endpoints or { }).${accessNode} or null;

  # Convert "...::1/64" to "...::/64" (best-effort, deterministic for our synthesis)
  prefix64FromHostAddr =
    addr:
    let
      ip = stripCidr addr;
    in
    if ip == null then
      null
    else if lib.hasSuffix "::1" ip then
      "${builtins.replaceStrings [ "::1" ] [ "::" ] ip}/64"
    else
      "${ip}/64";

in
topo
// {
  links = lib.mapAttrs (
    lname: l:
    if !(isPolicyAccess lname l) then
      l
    else
      let
        ms = l.members or [ ];
        accessNode = if lib.head ms == policyNode then builtins.elemAt ms 1 else lib.head ms;

        epAccess = getEp l accessNode;
        epPolicy = getEp l policyNode;

        vid = getTenantVid epAccess;

        # gateways must be plain IPs, not CIDR strings
        gw4 = stripCidr epPolicy.addr4;
        gw6 = stripCidr epPolicy.addr6;

        via4toAccess = stripCidr epAccess.addr4;
        via6toAccess = stripCidr epAccess.addr6;

        # Look up tenant LAN endpoint to fetch addr6Public synthesized by tenant-lan.nix
        tenantLanEp = if vid == null then null else tenantLanEpFor accessNode vid;

        tenantGuaPrefix =
          if tenantLanEp != null && tenantLanEp ? addr6Public then
            prefix64FromHostAddr tenantLanEp.addr6Public
          else
            null;

        accessRoutes4 = [
          {
            dst = "0.0.0.0/0";
            via4 = gw4;
          }
        ];

        accessRoutes6 = [
          {
            dst = "::/0";
            via6 = gw6;
          }
        ];

        policyRoutes4 = [
          {
            dst = tenant4Dst vid;
            via4 = via4toAccess;
          }
        ];

        policyRoutes6 = [
          {
            dst = tenant6DstUla vid;
            via6 = via6toAccess;
          }
        ]
        ++ lib.optional (tenantGuaPrefix != null) {
          dst = tenantGuaPrefix;
          via6 = via6toAccess;
        };
      in
      setEp
        (setEp l accessNode (
          epAccess
          // {
            routes4 = (epAccess.routes4 or [ ]) ++ accessRoutes4;
            routes6 = (epAccess.routes6 or [ ]) ++ accessRoutes6;
          }
        ))
        policyNode
        (
          epPolicy
          // {
            routes4 = (epPolicy.routes4 or [ ]) ++ policyRoutes4;
            routes6 = (epPolicy.routes6 or [ ]) ++ policyRoutes6;
          }
        )
  ) links;
}
