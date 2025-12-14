{ config, pkgs, lib, inputs, ... }:

{
  #################################
  # SOPS PPP SECRETS
  #################################
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  #################################
  # HOST NETWORKING (PURE L2)
  #################################
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  #################################
  # KERNEL / PPP
  #################################
  boot.kernelModules = [
    "ppp_generic"
    "pppox"
    "pppoe"
    "slhc"
  ];

  services.udev.extraRules = ''
    KERNEL=="ppp", MODE="0666"
  '';

  #################################
  # VLAN 6 -> BRIDGE
  #################################
  systemd.network.netdevs."10-ens19-vlan6" = {
    netdevConfig = {
      Name = "ens19.6";
      Kind = "vlan";
    };
    vlanConfig.Id = 6;
  };

  systemd.network.netdevs."20-br-wan6" = {
    netdevConfig = {
      Name = "br-wan6";
      Kind = "bridge";
    };
  };

  systemd.network.networks."20-br-wan6" = {
    matchConfig.Name = "br-wan6";
    linkConfig.RequiredForOnline = "no";
    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
    };
  };

  systemd.network.networks."30-ens19" = {
    matchConfig.Name = "ens19";
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      VLAN = [ "ens19.6" ];
    };
  };

  systemd.network.networks."40-ens19.6" = {
    matchConfig.Name = "ens19.6";
    networkConfig = {
      Bridge = "br-wan6";
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
    };
  };

  #################################
  # DISABLE RA (HOST)
  #################################
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.accept_ra" = 0;
    "net.ipv6.conf.default.accept_ra" = 0;
  };

  #################################
  # PPPoE CONTAINER
  #################################
  containers.pppoe-test = {
    autoStart = true;
    privateNetwork = true;

    extraVeths.wan.hostBridge = "br-wan6";

    allowedDevices = [
      { node = "/dev/ppp"; modifier = "rw"; }
    ];

    bindMounts."/dev/ppp" = {
      hostPath = "/dev/ppp";
      isReadOnly = false;
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    config = { pkgs, lib, ... }: {

      system.stateVersion = "24.11";

      #################################
      # BASE
      #################################
      services.dbus.enable = true;

      environment.systemPackages = with pkgs; [
        networkmanager
        ppp
        kea
        iproute2
        tcpdump
        curl
        bind.dnsutils
      ];

      #################################
      # DNS
      #################################
      environment.etc."resolv.conf".enable = false;
      services.resolved.enable = false;

      systemd.tmpfiles.rules = [
        "L+ /etc/resolv.conf - - - - /run/NetworkManager/resolv.conf"
      ];

      networking.useDHCP = lib.mkForce false;
      networking.useHostResolvConf = lib.mkForce false;

      #################################
      # DISABLE RA (CONTAINER)
      #################################
      boot.kernel.sysctl = {
        "net.ipv6.conf.all.accept_ra" = 0;
        "net.ipv6.conf.default.accept_ra" = 0;
      };

      #################################
      # NETWORKMANAGER (IPv4 ONLY)
      #################################
      networking.useNetworkd = false;

      networking.networkmanager = {
        enable = true;
        dns = "default";
      };

      #################################
      # PPPoE PROFILE (IPv6 OFF)
      #################################
      environment.etc."NetworkManager/system-connections/isp-pppoe.nmconnection" = {
        mode = "0600";
        text = ''
[connection]
id=pppoe-wan
uuid=22b16008-dffa-4ffb-8023-d99a8588fa02
type=pppoe
interface-name=wan

[ethernet]

[pppoe]
username=${builtins.readFile config.sops.secrets.pppoe-username.path}
password=${builtins.readFile config.sops.secrets.pppoe-password.path}

[ipv4]
method=auto

[ipv6]
method=disabled

[proxy]
        '';
      };

      #################################
      # KEA DHCPv6 CLIENT CONFIG
      #################################
      environment.etc."kea/kea-dhcp6.conf".text = ''
{
  "Dhcp6": {
    "interfaces-config": {
      "interfaces": [ "ppp0" ]
    },

    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/dhcp6.leases"
    },

    "preferred-lifetime": 7200,
    "valid-lifetime": 14400,

    "dhcp-ddns": {
      "enable-updates": false
    },

    "pd-pools": [
      {
        "prefix": "::",
        "prefix-len": 48,
        "delegated-len": 48
      }
    ]
  }
}
      '';

      #################################
      # KEA DHCPv6 CLIENT SERVICE
      #################################
      systemd.services.kea-dhcp6 = {
        description = "Kea DHCPv6 client (IA_NA + IA_PD /48) on ppp0";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          ExecStart = "${pkgs.kea}/bin/kea-dhcp6 -c /etc/kea/kea-dhcp6.conf";
          Restart = "always";
          RestartSec = 5;
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        };
      };
    };
  };
}

