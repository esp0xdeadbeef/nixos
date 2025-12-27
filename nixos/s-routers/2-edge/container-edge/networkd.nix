{ pkgs, lib, ... }:
{
  networking.useNetworkd = true;
  systemd.network.enable = true;

  networking.useDHCP = false;
  networking.networkmanager.enable = false;

  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # Uplink/transit: lan1010
  #systemd.network.networks."10-lan1010-uplink" = {
  #  matchConfig.Name = "lan1010";

  #  networkConfig = {
  #    Address = "10.255.255.2/30";
  #    Gateway = "10.255.255.1";

  #    IPv6AcceptRA = true;
  #    IPv6Forwarding = true;
  #    DHCP = "ipv6";
  #  };

  #  dhcpV6Config = {
  #    UseAddress = true;
  #    UseDelegatedPrefix = false;
  #  };
  #};

  #systemd.network.networks."00-ignore-lan1010" = {
  #  matchConfig.Name = "lan1010";
  #  linkConfig.Unmanaged = true;
  #};

  systemd.network.networks."10-lan1010" = {
    matchConfig.Name = "lan1010";

    networkConfig = {
      Address = [
        "10.255.255.2/30"
        "fd42:dead:beef:100::2/64"
      ];
      Gateway = [
        "10.255.255.1"
        "fd42:dead:beef:100::1"
      ];

      #IPv6AcceptRA = true;
      IPv6AcceptRA = false;
      IPv6Forwarding = true;
      #DHCP = "ipv6";
      DHCP = "no";
    };

    #dhcpV6Config = {
    #  UseAddress = true;
    #  UseDelegatedPrefix = false;
    #};

    #ipv6AcceptRAConfig = {
    #  UseAutonomousPrefix = true;
    #};
  };

  # =========================
  # LAN (lan7)
  # =========================
  systemd.network.networks."20-lan7" = {
    matchConfig.Name = "lan7";

    networkConfig = {
      Address = "10.13.37.1/24";

      IPv6AcceptRA = false;
      IPv6Forwarding = true;
    };
  };

  systemd.services.write-temp-10-lan1010-network = {

    after = [ "basic.target" ];
    wants = [ "basic.target" ];

    serviceConfig = {
      ExecStart = pkgs.writeShellScript "write-temp-10-lan1010-network-execstart" ''
        set -euo pipefail
        set -x
        mkdir -p /etc/systemd/network
        echo '
        [Match]
        Name=lan1010

        [Network]
        Address=10.255.255.2/30
        Gateway=10.255.255.1

        IPv6AcceptRA=yes
        IPv6Forwarding=yes
        DHCP=ipv6

        [DHCPv6]
        UseAddress=yes
        UseDelegatedPrefix=yes

        [IPv6AcceptRA]
        UseAutonomousPrefix=yes
        ' | tee /etc/systemd/network/10-lan1010.network


        echo '
        [Match]
        Name=lan7

        [Network]
        Address=10.13.37.1/24

        IPv6SendRA=yes
        IPv6AcceptRA=no
        IPv6Forwarding=yes

        DHCPPrefixDelegation=yes

        [DHCPPrefixDelegation]
        SubnetId=1
        PrefixLength=64

        [IPv6SendRA]
        Managed=no
        OtherInformation=no

        '| tee /etc/systemd/network/20-lan7.network
        systemctl restart systemd-networkd.service

      '';

      Restart = "on-failure";
      RestartSec = 10;
    };

  };
  #systemd.network.networks."10-lan1010-uplink" = {
  #  matchConfig.Name = "lan1010";

  #  networkConfig = {
  #    Address = "10.255.255.2/30";
  #    Gateway = "10.255.255.1";

  #    IPv6AcceptRA = true;
  #    IPv6Forwarding = true;
  #    DHCP = "ipv6";
  #  };

  #  dhcpV6Config = {
  #    UseAddress = true;
  #    UseDelegatedPrefix = false;
  #  };

  #  ipv6AcceptRAConfig = {
  #    UseAutonomousPrefix = true;
  #  };
  #};

  #systemd.network.networks."20-lan7" = {
  #  matchConfig.Name = "lan7";
  #  networkConfig = {
  #    Address = "10.13.37.1/24";
  #
  #    IPv6SendRA = true;
  #    IPv6AcceptRA = false;
  #    IPv6Forwarding = true;
  #    DHCPPrefixDelegation = true;
  #  };

  #  ipv6SendRAConfig = {
  #    Managed = false;
  #    OtherInformation = false;
  #  };
  #};

  # LANs: receive delegated prefixes and advertise them
  #systemd.network.networks."20-lan2" = {
  #  matchConfig.Name = "lan2";
  #  networkConfig = {
  #    Address = "192.168.1.1/24";
  #    IPv6SendRA = true;
  #    IPv6AcceptRA = false;
  #    IPv6Forwarding = true;
  #    DHCPPrefixDelegation = true;
  #  };
  #};

  #systemd.network.networks."20-lan3" = {
  #  matchConfig.Name = "lan3";
  #  networkConfig = {
  #    Address = "192.168.3.1/24";
  #    IPv6SendRA = true;
  #    IPv6AcceptRA = false;
  #    IPv6Forwarding = true;
  #    DHCPPrefixDelegation = true;
  #  };
  #};
  #systemd.network.networks."20-lan10" = {
  #  matchConfig.Name = "lan10";
  #  networkConfig = {
  #    Address = "192.168.10.1/24";
  #    IPv6SendRA = true;
  #    IPv6AcceptRA = false;
  #    IPv6Forwarding = true;
  #    DHCPPrefixDelegation = true;
  #  };
  #};
  #systemd.network.networks."20-lan1000" = {
  #  matchConfig.Name = "lan1000";
  #  networkConfig = {
  #    Address = "192.168.100.1/24";
  #    IPv6SendRA = true;
  #    IPv6AcceptRA = false;
  #    IPv6Forwarding = true;
  #    DHCPPrefixDelegation = true;
  #  };
  #};

}
