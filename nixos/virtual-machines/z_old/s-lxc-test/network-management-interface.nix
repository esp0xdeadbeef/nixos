{
  config,
  pkgs,
  lib,
  ...
}:

{
  networking = {
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "192.168.1.4";
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
