{ pkgs, lib, ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # Uplink/transit: lan1010
  systemd.network.networks."10-lan1010-uplink" = {
    matchConfig.Name = "lan1010";

    networkConfig = {
      Address = "10.255.255.2/30";
      Gateway = "10.255.255.1";

      IPv6AcceptRA = true;
      IPv6Forwarding = true;
      DHCP = "ipv6";
    };

    dhcpV6Config = {
      UseDelegatedPrefix = true;
      PrefixDelegationHint = "::/56";
    };
  };

  # LANs: receive delegated prefixes and advertise them
  systemd.network.networks."20-lan2" = {
    matchConfig.Name = "lan2";
    networkConfig = {
      Address = "192.168.1.1/24";
      IPv6SendRA = true;
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
      DHCPPrefixDelegation = true;
    };
  };

  systemd.network.networks."20-lan3" = {
    matchConfig.Name = "lan3";
    networkConfig = {
      Address = "192.168.3.1/24";
      IPv6SendRA = true;
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
      DHCPPrefixDelegation = true;
    };
  };
  systemd.network.networks."20-lan10" = {
    matchConfig.Name = "lan10";
    networkConfig = {
      Address = "192.168.10.1/24";
      IPv6SendRA = true;
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
      DHCPPrefixDelegation = true;
    };
  };
  systemd.network.networks."20-lan1000" = {
    matchConfig.Name = "lan1000";
    networkConfig = {
      Address = "192.168.100.1/24";
      IPv6SendRA = true;
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
      DHCPPrefixDelegation = true;
    };
  };

}
