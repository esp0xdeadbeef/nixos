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
  # VLAN 2 -> BRIDGE
  #################################
  systemd.network.netdevs."10-ens21-vlan2" = {
    netdevConfig = {
      Name = "ens21.2";
      Kind = "vlan";
    };
    vlanConfig.Id = 2;
  };

  systemd.network.netdevs."20-br-lan2" = {
    netdevConfig = {
      Name = "br-lan2";
      Kind = "bridge";
    };
  };

  systemd.network.networks."20-br-lan2" = {
    matchConfig.Name = "br-lan2";
    linkConfig.RequiredForOnline = "no";
    networkConfig = {
      ConfigureWithoutCarrier = true;
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
    };
  };

  systemd.network.networks."30-ens21" = {
    matchConfig.Name = "ens21";
    networkConfig = {
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
      VLAN = [ "ens21.2" ];
    };
  };

  systemd.network.networks."40-ens21.2" = {
    matchConfig.Name = "ens21.2";
    networkConfig = {
      Bridge = "br-lan2";
      DHCP = "no";
      IPv6AcceptRA = false;
      LinkLocalAddressing = "no";
    };
  };



  #################################
  # DISABLE RA (HOST)
  #################################
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
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
    extraVeths.eth1.hostBridge = "br-lan2";

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

    #################################
    # CONTAINER SYSTEM
    #################################
    config = { pkgs, lib, ... }: {

      system.stateVersion = "24.11";

      services.dbus.enable = true;

      #################################
      # PACKAGES
      #################################
      environment.systemPackages = with pkgs; [
        networkmanager
        ppp
        odhcp6c
        iproute2
        tcpdump
        curl
        bind.dnsutils
      ];


networking = {
  firewall = {
    enable = true;
    
    # Allows the entire interface through the firewall.
    trustedInterfaces = [
      "eth1"
    ];

    # Allows individual ports through the firewall.
    interfaces = {
      eth1 = {
        allowedUDPPorts = [
          # DNS
          53
          # DHCP
          67
          # You may want to allow more ports such as ipv6 and other services here.
        ];
      };
    };
  };
};
      networking.nat = {
    enable = true;

    # Traffic enters from ppp0
    internalInterfaces = [ "eth1" ];
    externalInterface = "ppp0";


  };
boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

environment.etc."NetworkManager/system-connections/lan-eth1.nmconnection" = {
  mode = "0600";
  text = ''
[connection]
id=lan-eth1
type=ethernet
interface-name=eth1
autoconnect=true

[ipv4]
method=manual
addresses=192.168.1.1/24
dns=192.168.1.1

[ipv6]
method=disabled
'';
};

environment.etc."kea/kea-dhcp4.conf" = {
  mode = "0644";
  text = ''
{
  "Dhcp4": {
    "interfaces-config": { "interfaces": [ "eth1" ] },
    "lease-database": {
      "type": "memfile",
      "persist": true,
      "name": "/var/lib/kea/dhcp4.leases"
    },
    "subnet4": [
      {
        "id": 1,
        "subnet": "192.168.1.0/24",
        "pools": [ { "pool": "192.168.1.100 - 192.168.1.200" } ],
        "option-data": [
          { "name": "routers", "data": "192.168.1.1" },
          { "name": "domain-name-servers", "data": "1.1.1.1, 8.8.8.8" }
        ]
      }
    ]
  }
}
'';
};

systemd.services.kea-dhcp4 = {
  description = "Kea DHCPv4 Server";
  wantedBy = [ "multi-user.target" ];

  after = [
    "NetworkManager.service"
    "NetworkManager-wait-online.service"
  ];

  requires = [
    "NetworkManager.service"
    "NetworkManager-wait-online.service"
  ];

  serviceConfig = {
          ExecStart = pkgs.writeShellScript "kea-dhcp4-execstart" ''
            set -euo pipefail
            set -x
            mkdir -p /var/run/kea || true
            ${pkgs.kea}/bin/kea-dhcp4 -c /etc/kea/kea-dhcp4.conf
          '';
ExecStartPost = pkgs.writeShellScript "kea-dhcp4-postcheck" ''
            set -euo pipefail
            LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 | tail -n 40)"

            if ! echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "listening on interface"; then
              echo "kea-dhcp4 not listening on any interface"
              exit 1
            fi

            sleep 3
            LOG="$(${pkgs.systemd}/bin/journalctl -u kea-dhcp4 -n 40)"
            if echo "$LOG" | ${pkgs.gnugrep}/bin/grep -q "DHCPSRV_OPEN_SOCKET_FAIL"; then
              echo "kea-dhcp4 failed to open sockets"
              exit 1
            fi

          '';
    Restart = "always";
    RestartSec = 2;
RuntimeDirectory = "kea";
          RuntimeDirectoryMode = "0755";

  };
};





      #################################
      # DNS (NM-OWNED)
      #################################
      environment.etc."resolv.conf".enable = false;
      services.resolved.enable = false;

      systemd.tmpfiles.rules = [
        "L+ /etc/resolv.conf - - - - /run/NetworkManager/resolv.conf"
      "d /run/kea 0777 root root -"
      "d /var/lib/kea 0777 root root -"
      ];

      networking.useDHCP = lib.mkForce false;
      networking.useHostResolvConf = lib.mkForce false;

      #################################
      # NETWORKMANAGER (IPv4 ONLY)
      #################################
      networking.useNetworkd = false;

      networking.networkmanager = {
        enable = true;
        dns = "default";
      };

      #################################
      # PPPoE PROFILE (IPv6 DISABLED)
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
      # DHCPv6 CLIENT (IA_NA + IA_PD /48)
      #################################
      systemd.services.odhcp6c = {
        description = "DHCPv6 client (IA_NA + IA_PD) on ppp0";
        wantedBy = [ "multi-user.target" ];

        after = [
          "NetworkManager.service"
          "NetworkManager-wait-online.service"
        ];

        requires = [
          "NetworkManager.service"
          "NetworkManager-wait-online.service"
        ];

        serviceConfig = {
          ExecStart = ''
            ${pkgs.odhcp6c}/sbin/odhcp6c \
              -f \
              -d \
              -s /bin/true \
              -P 48 \
              ppp0
          '';
          Restart = "always";
          RestartSec = 5;
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
          AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" ];
        };
      };
    };
  };
}

