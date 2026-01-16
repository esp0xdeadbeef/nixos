{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "ens21";
  wanIf = "ens19";
in
{
  ## Secrets
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  ## Network backend
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  ## Management interface
  networking = {
    interfaces.ens20.ipv4.addresses = [
      {
        address = "192.168.1.6";
        prefixLength = 24;
      }
    ];

    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens20";
    };
  };

  ## Netdevs
  systemd.network.netdevs = {
    ## LAN VLAN 1010
    "10-${lanIf}-vlan1010" = {
      netdevConfig = {
        Name = "${lanIf}.1010";
        Kind = "vlan";
      };
      vlanConfig.Id = 1010;
    };

    ## LAN bridge
    "20-br-vlan1010" = {
      netdevConfig = {
        Name = "br-vlan1010";
        Kind = "bridge";
      };
    };

    ## WAN VLAN 6
    "10-${wanIf}-vlan6" = {
      netdevConfig = {
        Name = "${wanIf}.6";
        Kind = "vlan";
      };
      vlanConfig.Id = 6;
    };

    ## WAN bridge
    "20-br-wan6" = {
      netdevConfig = {
        Name = "br-wan6";
        Kind = "bridge";
      };
    };
  };

  ## Networks
  systemd.network.networks = {
    ## LAN parent
    "20-${lanIf}" = {
      matchConfig.Name = lanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
        VLAN = [ "${lanIf}.1010" ];
      };
    };

    ## LAN VLAN → bridge
    "30-${lanIf}.1010" = {
      matchConfig.Name = "${lanIf}.1010";
      networkConfig.Bridge = "br-vlan1010";
    };

    ## LAN bridge
    "60-br-vlan1010" = {
      matchConfig.Name = "br-vlan1010";
      networkConfig.ConfigureWithoutCarrier = true;
    };

    ## WAN parent
    "40-${wanIf}" = {
      matchConfig.Name = wanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
        VLAN = [ "${wanIf}.6" ];
      };
    };

    ## WAN VLAN → bridge
    "50-${wanIf}.6" = {
      matchConfig.Name = "${wanIf}.6";
      networkConfig.Bridge = "br-wan6";
    };

    ## WAN bridge
    "60-br-wan6" = {
      matchConfig.Name = "br-wan6";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };

  ## Container
  containers.pppoe-wan-to-downstream = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = {
      lan1010.hostBridge = "br-vlan1010";
      wan.hostBridge = "br-wan6";
    };

    allowedDevices = [
      {
        node = "/dev/ppp";
        modifier = "rw";
      }
    ];

    bindMounts = {
      "/dev/ppp" = {
        hostPath = "/dev/ppp";
        isReadOnly = false;
      };

      "/run/secrets/pppoe-username" = {
        hostPath = config.sops.secrets.pppoe-username.path;
        isReadOnly = true;
      };

      "/run/secrets/pppoe-password" = {
        hostPath = config.sops.secrets.pppoe-password.path;
        isReadOnly = true;
      };
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    config = ./container-core-router/configuration.nix;
  };
}
