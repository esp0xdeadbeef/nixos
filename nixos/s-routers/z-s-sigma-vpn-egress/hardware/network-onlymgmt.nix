{
  config,
  pkgs,
  lib,
  ...
}:

let
  management_interface = "eth0";
  upstream_VPN_interface = "eth1";
  vpnNATInterface = "eth2";

  vpnInterface = "tun0";
  vpnConfBasePath = "/etc/vpn";
  vpnConfPath = "${vpnConfBasePath}/${vpnInterface}.conf";
  vpnIPv4WithMask = "10.90.0.1/24";
  vpnIPv6WithMask = "fd90:dead:beef::100/64";

  # ignore this
  vrf_table_vpn = 10;
  vrf_name_vpn = "vrf-vpn";

in
{

  environment.systemPackages = with pkgs; [
    # coreutils
    # python3
    # coreutils
    dnsutils # dig
    openvpn
    wireguard-tools
    tcpdump
    traceroute
    nftables
    dhcpcd
    tmux
  ];

  networking.networkmanager.enable = false;

  #systemd.network.networks."10-mgmt" = {
  #  matchConfig.Name = management_interface;
  #  networkConfig.DHCP = "yes";
  #  routingPolicyRules = [
  #    {
  #      Priority = 100;
  #      From = "192.168.1.0/24"; # or just your mgmt IP /32
  #      Table = "main";
  #    }
  #  ];
  #};
  networking = {
    interfaces.ens18 = {
      ipv4.addresses = [
        {
          address = "192.168.1.3";
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
