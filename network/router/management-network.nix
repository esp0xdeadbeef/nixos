{
  config,
  pkgs,
  ...
}:
{

  # networking = {
  #   hostId = "deadb33f";
  #   hostName = "nixos";
  #   domain = "example.com";
  #   dhcpcd.enable = false;
  #   interfaces.enp2s1.ipv4.addresses = [
  #     {
  #       address = "192.168.1.2";
  #       prefixLength = 28;
  #     }
  #   ];
  #   vlans = {
  #     vlan100 = {
  #       id = 100;
  #       interface = "enp2s0";
  #     };
  #     vlan101 = {
  #       id = 101;
  #       interface = "enp2s0";
  #     };
  #   };
  #   interfaces.vlan100.ipv4.addresses = [
  #     {
  #       address = "10.1.1.2";
  #       prefixLength = 24;
  #     }
  #   ];
  #   interfaces.vlan101.ipv4.addresses = [
  #     {
  #       address = "10.10.10.3";
  #       prefixLength = 24;
  #     }
  #   ];
  #   defaultGateway = "192.168.1.1";
  #   nameservers = [
  #     "1.1.1.1"
  #     "8.8.8.8"
  #   ];
  # };

  networking = {

    # hostName = "s-router-vpn-1";
    # nameservers = [ "${publicDnsServer}" ];
    # firewall.enable = false;

    interfaces = {
      ens18 = {
        useDHCP = true;
      };
    #   ens19 = {
    #     useDHCP = false;
    #     ipv4.addresses = [{
    #       address = "10.13.84.1";
    #       prefixLength = 24;
    #     }];
    #   };
    #   enp3s0 = {
    #     useDHCP = false;
    #   };
    #   enp4s0 = {
    #     useDHCP = false;
    #   };
    };

    # nftables = {
    #   enable = true;
    #   ruleset = ''
    #     table ip filter {
    #       chain input {
    #         type filter hook input priority 0; policy drop;

    #         iifname { "enp2s0" } accept comment "Allow local network to access the router"
    #         iifname "enp1s0" ct state { established, related } accept comment "Allow established traffic"
    #         iifname "enp1s0" icmp type { echo-request, destination-unreachable, time-exceeded } counter accept comment "Allow select ICMP"
    #         iifname "enp1s0" counter drop comment "Drop all other unsolicited traffic from wan"
    #       }
    #       chain forward {
    #         type filter hook forward priority 0; policy drop;
    #         iifname { "enp2s0" } oifname { "enp1s0" } accept comment "Allow trusted LAN to WAN"
    #         iifname { "enp1s0" } oifname { "enp2s0" } ct state established, related accept comment "Allow established back to LANs"
    #       }
    #     }

    #     table ip nat {
    #       chain postrouting {
    #         type nat hook postrouting priority 100; policy accept;
    #         oifname "enp1s0" masquerade
    #       }
    #     }

    #     table ip6 filter {
    #       chain input {
    #         type filter hook input priority 0; policy drop;
    #       }
    #       chain forward {
    #         type filter hook forward priority 0; policy drop;
    #       }
    #     }
    #   '';
    # };
  };

}
