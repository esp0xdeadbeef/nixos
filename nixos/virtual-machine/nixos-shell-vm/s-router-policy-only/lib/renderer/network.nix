{ lib }:

let
  routeHelpers = import ./routes.nix { inherit lib; };
  inherit (routeHelpers) routesFor;
in
d: {
  name = "20-${d.renderedIfName}";
  value = {
    matchConfig.Name = d.renderedIfName;

    linkConfig = {
      ActivationPolicy = "always-up";
      RequiredForOnline = false;
    };

    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      IPv4Forwarding = true;
      IPv6Forwarding = true;
      ConfigureWithoutCarrier = true;
    };

    addresses =
      (lib.optional (d.backingIface ? addr4) { Address = d.backingIface.addr4; })
      ++ (lib.optional (d.backingIface ? addr6) { Address = d.backingIface.addr6; });

    routes = routesFor d.backingIface;
  };
}
