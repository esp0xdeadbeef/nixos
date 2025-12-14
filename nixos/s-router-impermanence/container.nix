{ config, pkgs, lib, inputs, ... }:

{

  # SOPS PPP secrets
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };
  ############################
  # HOST NETWORKING (PURE L2)
  ############################
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  ############################
  # KERNEL / PPP
  ############################
  boot.kernelModules = [
    "ppp_generic"
    "pppox"
    "pppoe"
    "slhc"
  ];

  services.udev.extraRules = ''
    KERNEL=="ppp", MODE="0666"
  '';

  ############################
  # VLAN 6 -> BRIDGE
  ############################
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

  ############################
  # DISABLE RA
  ############################
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

    ############################
    # CONTAINER SYSTEM
    ############################
    config = { pkgs, ... }: {
      environment.etc."resolv.conf".enable = false;


      networking.useNetworkd = false;
      networking.networkmanager = {
        enable = true;
        dns = "default";
      };

      services.dbus.enable = true;

      ############################
      # PERSISTENT PPPoE PROFILE
      # (SUPPORTED METHOD)
      ############################
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
addr-gen-mode=default
method=auto

[proxy]
        '';
      };
      
      services.resolved.enable = false;
      systemd.tmpfiles.rules = [
        "L+ /etc/resolv.conf - - - - /run/NetworkManager/resolv.conf"
      ];
      systemd.services.resolvconf.enable = false;

      networking.useDHCP = lib.mkForce false;
      networking.useHostResolvConf = lib.mkForce false;

      environment.systemPackages = with pkgs; [
        networkmanager
        ppp
        iproute2
        tcpdump
        curl
        bind.dnsutils
      ];

      system.stateVersion = "24.11";
    };
  };
}

