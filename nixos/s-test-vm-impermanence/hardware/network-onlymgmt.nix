{
  config,
  pkgs,
  lib,
  ...
}:
{

  networking.networkmanager.enable = false;

  networking = {
    interfaces.ens18 = {
      ipv4.addresses = [
        {
          address = "192.168.1.5";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens18";
    };
  };

  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
