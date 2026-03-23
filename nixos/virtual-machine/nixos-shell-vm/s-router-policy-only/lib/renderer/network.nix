{ lib }:

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

    addresses = d.addresses;
    routes = d.routes;
  };
}
