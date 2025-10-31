{
  config,
  lib,
  pkgs,
  ...
}:

let
  wan = "ens19";
  wanVlan = "ens19.6";
  userSecret = "pppoe-username";
  passSecret = "pppoe-password";
in
{
  networking.useNetworkd = true;
  networking.enableIPv6 = true;
  systemd.network.enable = true;

  # VLAN 6 for PPPoE WAN
  systemd.network.netdevs."10-${wanVlan}" = {
    netdevConfig = {
      Name = wanVlan;
      Kind = "vlan";
      MTUBytes = 1508;
    };
    vlanConfig.Id = 6;
  };

  systemd.network.networks."10-${wan}" = {
    matchConfig.Name = wan;
    networkConfig.VLAN = [ wanVlan ];
  };

  systemd.network.networks."20-${wanVlan}" = {
    matchConfig.Name = wanVlan;
  };

  # PPPoE
  services.pppd = {
    enable = true;
    peers.pppoe = {
      enable = true;
      autostart = true;
      config = ''
        plugin pppoe.so ${wanVlan}
        user "$(cat ${config.sops.secrets.${userSecret}.path})"
        password "$(cat ${config.sops.secrets.${passSecret}.path})"

        noipdefault
        defaultroute
        usepeerdns

        mtu 1500
        mru 1500

        persist
        maxfail 0
        holdoff 5
        lcp-echo-interval 10
        lcp-echo-failure 6

        +ipv6
        ipv6cp-use-ipaddr
      '';
    };
  };

  # IPv6 Prefix Delegation from ISP
  systemd.network.networks."30-ppp0" = {
    matchConfig.Name = "ppp0";
    networkConfig = {
      DHCP = "ipv6";
      IPv6AcceptRA = true;
    };
  };

  # SOPS PPP secrets
  sops.secrets.${userSecret} = { };
  sops.secrets.${passSecret} = { };
}
