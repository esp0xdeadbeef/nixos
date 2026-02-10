{
  lib,
  pkgs,
  ulaPrefix,
  tenantV4Base,
}:

nodeName: topo:

let
  links = lib.filterAttrs (_: l: lib.elem nodeName (l.members or [ ])) (topo.links or { });

  # Deep JSON sanitizer: eliminate lambdas AND primops anywhere in the tree
  sanitize =
    x:
    let
      t = builtins.typeOf x;
    in
    if t == "lambda" || t == "primop" then
      "<function>"
    else if builtins.isList x then
      map sanitize x
    else if builtins.isAttrs x then
      lib.mapAttrs (_: v: sanitize v) x
    else if t == "path" then
      toString x
    else
      x;

  getTenantVid =
    ep:
    if ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

in
sanitize {
  node = nodeName;

  interfaces = lib.mapAttrs (
    _lname: l:
    let
      ep = (l.endpoints or { }).${nodeName} or { };
    in
    {
      kind = l.kind or null;
      vlanId = l.vlanId or null;

      tenantVlanId = getTenantVid ep;

      addr4 = ep.addr4 or null;
      addr6 = ep.addr6 or null;
      addr6Public = ep.addr6Public or null;

      routes4 = ep.routes4 or [ ];
      routes6 = ep.routes6 or [ ];
      ra6Prefixes = ep.ra6Prefixes or [ ];

      export = ep.export or false;
      gateway = ep.gateway or false;
    }
  ) links;
}
