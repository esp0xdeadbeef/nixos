# ./lib/renderer/routes.nix
{ lib }:

let
  normalizeDst =
    dst:
    if dst == "0000:0000:0000:0000:0000:0000:0000:0000/0" then "::/0" else dst;

  routeKeep =
    r:
    let
      dst = r.dst or null;
      proto = r.proto or "";
    in
    dst != null && !(builtins.elem proto [ "connected" ]);

  mkRoute =
    r:
    {
      Destination = normalizeDst r.dst;
    }
    // lib.optionalAttrs (r ? via4) { Gateway = r.via4; }
    // lib.optionalAttrs (r ? via6) { Gateway = r.via6; };

  routesFor =
    iface:
    lib.unique (
      map mkRoute (
        lib.filter routeKeep (
          (iface.routes.ipv4 or [ ])
          ++ (iface.routes.ipv6 or [ ])
        )
      )
    );
in
{
  inherit
    normalizeDst
    routeKeep
    mkRoute
    routesFor
    ;
}
