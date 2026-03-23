{ lib }:

{
  routesFor =
    iface:
    if !(iface ? routes) then
      abort ''
        renderer/routes.nix: iface.routes is missing

        iface:
        ${builtins.toJSON iface}
      ''
    else if !(builtins.isList iface.routes) then
      abort ''
        renderer/routes.nix: iface.routes must be a list

        iface:
        ${builtins.toJSON iface}
      ''
    else
      map (
        route:
        if !(builtins.isAttrs route) then
          abort ''
            renderer/routes.nix: route entry must be an attribute set

            route:
            ${builtins.toJSON route}

            iface:
            ${builtins.toJSON iface}
          ''
        else if !(route ? Destination) || !(builtins.isString route.Destination) || route.Destination == "" then
          abort ''
            renderer/routes.nix: route entry missing Destination

            route:
            ${builtins.toJSON route}

            iface:
            ${builtins.toJSON iface}
          ''
        else if route ? Gateway && (!(builtins.isString route.Gateway) || route.Gateway == "") then
          abort ''
            renderer/routes.nix: route entry has invalid Gateway

            route:
            ${builtins.toJSON route}

            iface:
            ${builtins.toJSON iface}
          ''
        else
          route
      ) iface.routes;
}
