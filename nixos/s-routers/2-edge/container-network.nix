{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "ens21";

  natVlans = [
    7
    1010
  ];
  #builtins.genList (i: i + 2) 2
  #++ builtins.genList (i: i + 10) 1
  #++ builtins.genList (i: i + 1000) 1
  #++ builtins.genList (i: i + 1010) 1;
in
{

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
    );

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
  );

  containers.container-edge = {
    autoStart = true;
    privateNetwork = true;

    extraVeths = lib.genAttrs (map (v: "lan${toString v}") natVlans) (
      name:
      let
        v = lib.toInt (lib.removePrefix "lan" name);
      in
      {
        hostBridge = "br-vlan${toString v}";
      }
    );

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    config = ./container-edge/configuration.nix;
  };
}
