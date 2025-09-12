{
  config,
  pkgs,
  lib,
  ...
}:

let
  phys0 = "phys0";
  vlanLan = "vlan-lan";
  vlanInt = "vlan-int";
  vpnIf = "wg0";
  subnet_nat = "192.168.80.0/24";
  gateway_nat = "192.168.80.1/24";
  gateway_nat_v6 = "fd80:dead:beef::1";
  subnet_nat_v6 = "fd80:dead:beef::/64";
in
{
  ########################################################
  # 1) SYSTEM PACKAGES & NETWORKMANAGER (host uplink NIC)
  ########################################################
  environment.systemPackages = with pkgs; [
    networkmanager
    networkmanager-openvpn
    wireguard-tools
    iproute2
    iptables
    sipcalc
    traceroute
  ];

  networking.networkmanager.enable = true;
  networking.networkmanager.unmanaged = [ phys0 ];
  networking.networkmanager.ensureProfiles.profiles = {
    "Wired connection 1" = {
      connection = {
        id = "Wired connection 1";
        type = "802-3-ethernet";
        interfaceName = "ens18";
        autoconnect = true;
      };
      ipv4 = {
        method = "auto";
        routeMetric = 50;
      };
      ipv6 = {
        method = "auto";
        routeMetric = 50;
      };
    };
  };

  ########################################################
  # 2) systemd-networkd (internal VLAN only)
  ########################################################
  networking.useNetworkd = true;
  systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

  # rename the physical link for matching
  systemd.network.links."10-phys0" = {
    matchConfig.PermanentMACAddress = "bc:24:11:28:1f:b6";
    linkConfig.Name               = phys0;
  };

  # trunk on phys0 carries only vlan-int
  systemd.network.networks."10-phys0" = {
    matchConfig.Name   = phys0;
    networkConfig.VLAN = [ vlanInt ];
  };

  # VLAN 20: internal network
  systemd.network.netdevs."30-${vlanInt}" = {
    netdevConfig.Kind = "vlan";
    netdevConfig.Name = vlanInt;
    vlanConfig.Id     = 20;
  };
  systemd.network.networks."30-${vlanInt}" = {
    matchConfig.Name = vlanInt;
    addresses = [
      { Address = "192.168.80.1/24"; }
      { Address = "fd80:dead:beef::1/64"; }
    ];
    networkConfig = {
      DHCP         = false;
      IPv6AcceptRA = false;
      DNS          = [ "1.1.1.1" ];
    };
  };

  ########################################################
  # 3) Kernel forwarding & sysctls
  ########################################################
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  ########################################################
  # 4) WireGuard (default-route via wg0)
  ########################################################
# systemd.services."wg0-reinit" = {
#   description = "Forcefully restart ${vpnIf} using wg-quick to apply postUp/preDown";
#   after = [ "network-online.target" ];
#   wantedBy = [ "multi-user.target" ];
#   requires = [ "network-online.target" ];
#   serviceConfig = {
#     Type = "oneshot";
#     RemainAfterExit = true;
#   };
#   script = ''
#     set -e
#     ${pkgs.wireguard-tools}/bin/wg-quick down ${vpnIf} || true
#     sleep 1
#     ${pkgs.wireguard-tools}/bin/wg-quick up ${vpnIf}
#   '';
# };
# systemd.services."wg-quick-wg0".serviceConfig = {
#   ExecStartPost = lib.mkForce [
#     "${pkgs.iproute2}/bin/ip route add default dev ${vpnIf} table 100"
#     "${pkgs.iproute2}/bin/ip rule add from ${subnet_nat} table 100 priority 100"

#     "${pkgs.iptables}/bin/iptables -A FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT"
#     "${pkgs.iptables}/bin/iptables -A FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT"
#     "${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${subnet_nat} -o ${vpnIf} -j MASQUERADE"

#     "${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT"
#     "${pkgs.iptables}/bin/ip6tables -A FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT"
#     "${pkgs.iptables}/bin/ip6tables -t nat -A POSTROUTING -s ${subnet_nat_v6} -o ${vpnIf} -j MASQUERADE"
#   ];

#   ExecStopPost = lib.mkForce [
#     "${pkgs.iproute2}/bin/ip rule del from ${subnet_nat} table 100 priority 100"
#     "${pkgs.iproute2}/bin/ip route del default dev ${vpnIf} table 100"

#     "${pkgs.iptables}/bin/iptables -D FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT"
#     "${pkgs.iptables}/bin/iptables -D FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT"
#     "${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${subnet_nat} -o ${vpnIf} -j MASQUERADE"

#     "${pkgs.iptables}/bin/ip6tables -D FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT"
#     "${pkgs.iptables}/bin/ip6tables -D FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT"
#     "${pkgs.iptables}/bin/ip6tables -t nat -D POSTROUTING -s ${subnet_nat_v6} -o ${vpnIf} -j MASQUERADE"
#   ];
# };



# WireGuard interface config (postUp/preDown will now run)
networking.wg-quick.interfaces.${vpnIf} = {
  configFile = "/root/tun0.conf";
  postUp = ''
    ip route add default dev ${vpnIf} table 100
    ip rule add from ${subnet_nat} table 100 priority 100

    ${pkgs.iptables}/bin/iptables -A FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT
    ${pkgs.iptables}/bin/iptables -A FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT
    ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${subnet_nat} -o ${vpnIf} -j MASQUERADE

    ${pkgs.ip6tables}/bin/ip6tables -A FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT
    ${pkgs.ip6tables}/bin/ip6tables -A FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT
    ${pkgs.ip6tables}/bin/ip6tables -t nat -A POSTROUTING -s ${subnet_nat_v6} -o ${vpnIf} -j MASQUERADE
  '';

  preDown = ''
    ip rule del from ${subnet_nat} table 100 priority 100
    ip route del default dev ${vpnIf} table 100

    ${pkgs.iptables}/bin/iptables -D FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT || true
    ${pkgs.iptables}/bin/iptables -D FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT || true
    ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${subnet_nat} -o ${vpnIf} -j MASQUERADE || true

    ${pkgs.ip6tables}/bin/ip6tables -D FORWARD -i ${vlanInt} -o ${vpnIf} -j ACCEPT || true
    ${pkgs.ip6tables}/bin/ip6tables -D FORWARD -i ${vpnIf} -o ${vlanInt} -j ACCEPT || true
    ${pkgs.ip6tables}/bin/ip6tables -t nat -D POSTROUTING -s ${subnet_nat_v6} -o ${vpnIf} -j MASQUERADE || true
  '';
  table = false;
};



  ########################################################
  # 6) Kea DHCP & RADVD
  ########################################################
  services.kea.dhcp4 = {
    enable = true;
    settings = {
      "interfaces-config" = {
        interfaces = [ vlanInt ];
      };
      subnet4 = [
        {
          id = 1;
          subnet = "192.168.80.0/24";
          pools = [ { pool = "192.168.80.10 - 192.168.80.200"; } ];
          # "option-data" = [
          #   { name = "routers"; code = 3; space = "dhcp4"; csv-format = "192.168.80.1"; }
          #   { name = "domain-name-servers"; code = 6; space = "dhcp4"; csv-format = "1.1.1.1"; }
          # ];
        }
      ];
    };
  };

  services.kea.dhcp6 = {
    enable = true;
    settings = {
      "interfaces-config" = {
        interfaces = [ vlanInt ];
      };
      subnet6 = [
        {
          id = 1;
          subnet = "fd80:dead:beef::/64";
          pools = [ { pool = "fd80:dead:beef::10 - fd80:dead:beef::200"; } ];
        }
      ];
    };
  };

  services.radvd.enable = true;
  services.radvd.config = ''
    interface ${vlanInt} {
      AdvSendAdvert     on;
      MinRtrAdvInterval 3;
      MaxRtrAdvInterval 10;
      prefix fd80:dead:beef::/64 {
        AdvOnLink     on;
        AdvAutonomous on;
      };
      RDNSS 2606:4700:4700::1111 {
        AdvRDNSSLifetime 800;
      };
    };
  '';
}
