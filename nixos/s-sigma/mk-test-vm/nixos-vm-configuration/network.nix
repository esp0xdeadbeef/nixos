{
  lib,
  pkgs,
  ...
}:
{
  networking = {
    dhcpcd.enable = false;

    vlans.vlan2 = {
      id = 2;
      interface = "enp1s0";
    };

    interfaces.vlan2.ipv4.addresses = [
      {
        address = "192.168.1.210";
        prefixLength = 24;
      }
    ];

    interfaces.vlan2.ipv4.routes = [
      {
        address = "0.0.0.0";
        prefixLength = 0;
        via = "192.168.1.1";
      }
    ];

    nameservers = [
      "192.168.1.1"
      "1.1.1.1"
    ];
  };

  networking.networkmanager.enable = true;

}
