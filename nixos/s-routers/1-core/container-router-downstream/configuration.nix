{ pkgs, lib, ... }:
{

  imports = [
    ./dns-dhcp.nix
    ./wan.nix
    ./debugging-packages.nix
    ./firewall.nix
  ];

  services.resolved.enable = false;

  system.stateVersion = "25.11";

  services.dbus.enable = true;
  programs.neovim = {
    enable = true;
    defaultEditor = true;
  };

  systemd.tmpfiles.rules = [
    "d /run/kea 0777 root root -"
    "d /var/lib/kea 0777 root root -"
    "d /etc/ppp/peers/ 0777 root root -"
  ];

  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;

  networking.useHostResolvConf = lib.mkForce false;

  networking.useNetworkd = true;

  networking.useDHCP = false;

  networking.interfaces = {
    lan2.ipv4.addresses = [
      {
        address = "192.168.1.1";
        prefixLength = 24;
      }
    ];
    lan3.ipv4.addresses = [
      {
        address = "192.168.3.1";
        prefixLength = 24;
      }
    ];
    lan10.ipv4.addresses = [
      {
        address = "192.168.10.1";
        prefixLength = 24;
      }
    ];
    lan1000.ipv4.addresses = [
      {
        address = "192.168.100.1";
        prefixLength = 24;
      }
    ];
    lan1010.ipv4.addresses = [
      {
        address = "10.255.255.1";
        prefixLength = 30;
      }
    ];
  };

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;

    # accept RA from ppp0
    "net.ipv6.conf.ppp0.accept_ra" = 2;

    # IPv6 routing ON
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;

    # REQUIRED for RA while forwarding
    "net.ipv6.conf.all.accept_ra" = 2;
    "net.ipv6.conf.default.accept_ra" = 2;

    # LAN interfaces MUST accept RA
    "net.ipv6.conf.lan2.accept_ra" = 2;
    "net.ipv6.conf.lan3.accept_ra" = 2;
    "net.ipv6.conf.lan10.accept_ra" = 2;
    "net.ipv6.conf.lan1000.accept_ra" = 2;
    "net.ipv6.conf.lan1010.accept_ra" = 2;

    # RA over bridges WILL NOT WORK without this
    "net.bridge.bridge-nf-call-ip6tables" = 0;
    "net.bridge.bridge-nf-call-iptables" = 0;
    "net.bridge.bridge-nf-call-arptables" = 0;
  };

  networking.nat = {
    enable = true;
    externalInterface = "ppp0";
    internalInterfaces = [
      "lan2"
      "lan3"
      "lan10"
      "lan1000"
      "lan1010"
    ];
  };

  #systemd.services.kea-dhcp-ddns.serviceConfig.EnvironmentFile = "-/var/lib/kea/tsig.env";

  #systemd.services.kea-dhcp-ddns.after = [ "kea-tsig-init.service" ];
  #systemd.services.kea-dhcp-ddns.wants = [ "kea-tsig-init.service" ];

  environment.etc."dhcpcd.conf".text = ''
    duid
    persistent
    noipv6rs
    noipv4
    ipv6only

    interface ppp0
      iaid 1
      ia_pd 1 lan2/0/64 lan3/1/64 lan10/2/64 lan1000/3/64 

  '';

}
