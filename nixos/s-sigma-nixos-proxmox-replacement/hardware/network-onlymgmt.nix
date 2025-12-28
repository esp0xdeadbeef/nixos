{
  config,
  pkgs,
  lib,
  ...
}:
{

  networking = {
    interfaces.ens18 = {
      ipv4.addresses = [
        {
          address = "192.168.1.71";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens18";
    };
  };

}
