{ lib, ... }:

{
  services.resolved.enable = true;
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;

    networks."10-eth0" = {
      matchConfig.Name = "eth0";

      networkConfig = {
        DHCP = "yes"; # v4 + v6
        IPv6AcceptRA = "yes";
      };

      dhcpV4Config = {
        UseDNS = "yes";
        UseDomains = "yes";
      };

      dhcpV6Config = {
        UseDNS = "yes";
      };
    };
    networks."10-eth1" = {
      matchConfig.Name = "eth1";

      networkConfig = {
        DHCP = "yes"; # v4 + v6
        IPv6AcceptRA = "yes";
      };

      dhcpV4Config = {
        UseDNS = "yes";
        UseDomains = "yes";
      };

      dhcpV6Config = {
        UseDNS = "yes";
      };
    };
  };


}
