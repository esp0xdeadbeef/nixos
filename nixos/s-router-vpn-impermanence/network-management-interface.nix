{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking = {
    interfaces.ens20 = {
      ipv4.addresses = [
        {
          address = "192.168.1.3";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens20";
    };
  };
}
