# lib/debug/50-wan.nix
let
  pkgs = import <nixpkgs> { };
  lib = pkgs.lib;

  routed = import ./30-routing.nix;

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

  wanLinks = lib.filterAttrs (_: l: (l.kind or null) == "wan") routed.links;

in
sanitize {
  wans = lib.mapAttrs (lname: l: {
    name = l.name or lname;
    vlanId = l.vlanId or null;
    carrier = l.carrier or null;

    endpoints = lib.mapAttrs (_node: ep: {
      addr4 = ep.addr4 or null;
      addr6 = ep.addr6 or null;
      routes4 = ep.routes4 or [ ];
      routes6 = ep.routes6 or [ ];
    }) (l.endpoints or { });
  }) wanLinks;
}
