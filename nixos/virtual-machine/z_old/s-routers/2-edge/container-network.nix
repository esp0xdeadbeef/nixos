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
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;
  sops.secrets.subnet-ipv6 = { };

  ########################################
  # NETDEVS: VLANs + BRIDGES
  ########################################
  systemd.network.netdevs =
    lib.genAttrs (map (v: "10-${lanIf}-vlan${toString v}") natVlans) (
      name:
      let
        v = lib.toInt (lib.last (lib.splitString "vlan" name));
      in
      {
        netdevConfig = {
          Name = "${lanIf}.${toString v}";
          Kind = "vlan";
        };
        vlanConfig.Id = v;
      }
    )
    // lib.genAttrs (map (v: "20-br-vlan${toString v}") natVlans) (
      name:
      let
        v = lib.toInt (lib.last (lib.splitString "vlan" name));
      in
      {
        netdevConfig = {
          Name = "br-vlan${toString v}";
          Kind = "bridge";
        };
      }
    );

  ########################################
  # NETWORKS
  ########################################
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
      networkConfig = {
        ConfigureWithoutCarrier = true;
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
      };
    }
  );

  ########################################
  # CONTAINER
  ########################################
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

    bindMounts = {
      "/run/secrets/subnet-ipv6" = {
        hostPath = config.sops.secrets.subnet-ipv6.path;
        isReadOnly = true;
      };
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
      "CAP_SYS_ADMIN"
    ];

    config = ./container-edge/configuration.nix;
  };
}
