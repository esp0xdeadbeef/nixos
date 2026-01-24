{ lib, ... }:

{
  services.resolved.enable = true;
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;

    networks."10-veth-game" = {
      matchConfig.Name = "veth-game";

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

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;
}
