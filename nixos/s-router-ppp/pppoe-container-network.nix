{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "ens21";
  wanIf = "ens19";

  natVlans = [ 1010 ]; # builtins.genList (i: i + 1010) 1; # 1010
  wanVlan = 6;
in
{
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  networking = {
    interfaces.ens20 = {
      ipv4.addresses = [
        {
          address = "192.168.1.2";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "ens20";
    };
  };

  systemd.network.netdevs =
    lib.genAttrs (map (v: "10-${lanIf}-vlan${toString v}") natVlans) (
      v:
      let
        id = lib.toInt (lib.last (lib.splitString "vlan" v));
      in
      {
        netdevConfig = {
          Name = "${lanIf}.${toString id}";
          Kind = "vlan";
        };
        vlanConfig.Id = id;
      }
    )
    // lib.genAttrs (map (v: "20-br-vlan${toString v}") natVlans) (
      v:
      let
        id = lib.toInt (lib.last (lib.splitString "vlan" v));
      in
      {
        netdevConfig = {
          Name = "br-vlan${toString id}";
          Kind = "bridge";
        };
      }
    )
    // {
      "10-${wanIf}-vlan${toString wanVlan}" = {
        netdevConfig = {
          Name = "${wanIf}.${toString wanVlan}";
          Kind = "vlan";
        };
        vlanConfig.Id = wanVlan;
      };

      "20-br-wan${toString wanVlan}" = {
        netdevConfig = {
          Name = "br-wan${toString wanVlan}";
          Kind = "bridge";
        };
      };
    };

  systemd.network.networks = {
    "20-${lanIf}" = {
      matchConfig.Name = lanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
        VLAN = map (v: "${lanIf}.${toString v}") natVlans;
      };
    };

    "40-${wanIf}" = {
      matchConfig.Name = wanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
        VLAN = [ "${wanIf}.${toString wanVlan}" ];
      };
    };

    "50-${wanIf}.${toString wanVlan}" = {
      matchConfig.Name = "${wanIf}.${toString wanVlan}";
      networkConfig.Bridge = "br-wan${toString wanVlan}";
    };
  }
  // lib.genAttrs (map (v: "30-${lanIf}.${toString v}") natVlans) (
    name:
    let
      v = lib.toInt (lib.last (lib.splitString "." name));
    in
    {
      matchConfig.Name = "${lanIf}.${toString v}";
      networkConfig.Bridge = "br-vlan${toString v}";
    }
  )
  // lib.genAttrs (map (v: "60-br-vlan${toString v}") natVlans) (
    name:
    let
      v = lib.toInt (lib.last (lib.splitString "vlan" name));
    in
    {
      matchConfig.Name = "br-vlan${toString v}";
      networkConfig.ConfigureWithoutCarrier = true;
    }
  )
  // {
    "60-br-wan${toString wanVlan}" = {
      matchConfig.Name = "br-wan${toString wanVlan}";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };

  containers.downstream-router = {
    autoStart = true;
    privateNetwork = true;

    extraVeths =
      lib.genAttrs (map (v: "lan${toString v}") natVlans) (
        name:
        let
          v = lib.toInt (lib.removePrefix "lan" name);
        in
        {
          hostBridge = "br-vlan${toString v}";
        }
      )
      // {
        wan.hostBridge = "br-wan${toString wanVlan}";
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
