{
  lib,
  pkgs,
  ...
}:
{

  networking.useNetworkd = true;
  systemd.network.enable = true;
  services.resolved.enable = false;

  networking.networkmanager.unmanaged = [
    "interface-name:eth1"
  ];

  #systemd.network.networks."eth1" = {
  #  matchConfig.Name = "eth1";
  #  networkConfig = {
  #    Address = "10.255.255.2/30";
  #    Gateway = "10.255.255.1";
  #    DNS = [
  #      "1.1.1.1"
  #      "8.8.8.8"
  #    ];
  #  };
  #};

}
