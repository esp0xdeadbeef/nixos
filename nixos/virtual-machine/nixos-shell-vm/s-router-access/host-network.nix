# ./host-config/network.nix
# FILE: s-router-access/host-config/network.nix
{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  cfg = import "${outPath}/library/100-fabric-routing/inputs";

  tenantVlans = cfg.tenantVlans;
  policyBase = cfg.policyAccessTransitBase or 100;

  transitVidFor = vid: policyBase + vid;

  mgmtParent = "eth1";
  mgmtVlanId = 2;
  mgmtVlanIf = "${mgmtParent}.${toString mgmtVlanId}";

  trunkParent = "eth0";

  uplinkBridge = "br-lan-trunk";

  lanBridgeFor = vid: "br-lan-${toString vid}";
  lanVlanIfFor = vid: "${trunkParent}.${toString vid}";

  transitBridgeFor = vid: "tr${toString (transitVidFor vid)}";
  transitVlanIfFor = vid: "${trunkParent}.${toString (transitVidFor vid)}";

  allVlansOnTrunk = (map lanVlanIfFor tenantVlans) ++ (map transitVlanIfFor tenantVlans);
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  ############################
  # NETDEVS
  ############################
  systemd.network.netdevs = lib.mkMerge (
    [
      #
      # Mgmt VLAN
      #
      {
        "04-${mgmtVlanIf}" = {
          netdevConfig = {
            Name = mgmtVlanIf;
            Kind = "vlan";
          };
          vlanConfig.Id = mgmtVlanId;
        };
      }

      #
      # Mgmt bridge
      #
      {
        "05-br-mgmt" = {
          netdevConfig = {
            Name = "br-mgmt";
            Kind = "bridge";
          };
          bridgeConfig = {
            STP = false;
            ForwardDelaySec = 0;
          };
        };
      }

      #
      # Uplink trunk bridge
      #
      {
        "10-${uplinkBridge}" = {
          netdevConfig = {
            Name = uplinkBridge;
            Kind = "bridge";
          };
          bridgeConfig = {
            STP = false;
            ForwardDelaySec = 0;
          };
        };
      }
    ]

    #
    # Per-tenant LAN bridges
    #
    ++ map (vid: {
      "12-${lanBridgeFor vid}" = {
        netdevConfig = {
          Name = lanBridgeFor vid;
          Kind = "bridge";
        };
        bridgeConfig = {
          STP = false;
          ForwardDelaySec = 0;
        };
      };
    }) tenantVlans

    #
    # Per-tenant transit bridges
    #
    ++ map (vid: {
      "20-${transitBridgeFor vid}" = {
        netdevConfig = {
          Name = transitBridgeFor vid;
          Kind = "bridge";
        };
        bridgeConfig = {
          STP = false;
          ForwardDelaySec = 0;
        };
      };
    }) tenantVlans

    #
    # Tenant LAN VLAN subinterfaces on eth0
    #
    ++ map (vid: {
      "30-${lanVlanIfFor vid}" = {
        netdevConfig = {
          Name = lanVlanIfFor vid;
          Kind = "vlan";
        };
        vlanConfig.Id = vid;
      };
    }) tenantVlans

    #
    # Transit VLAN subinterfaces on eth0
    #
    ++ map (vid: {
      "31-${transitVlanIfFor vid}" = {
        netdevConfig = {
          Name = transitVlanIfFor vid;
          Kind = "vlan";
        };
        vlanConfig.Id = transitVidFor vid;
      };
    }) tenantVlans
  );

  ############################
  # NETWORKS
  ############################
  systemd.network.networks = lib.mkMerge (

    [
      #
      # Mgmt parent NIC
      #
      {
        "04-mgmt-parent" = {
          matchConfig.Name = mgmtParent;
          networkConfig = {
            DHCP = "no";
            VLAN = [ mgmtVlanIf ];
            ConfigureWithoutCarrier = true;
          };
        };
      }

      #
      # Mgmt VLAN → br-mgmt
      #
      {
        "05-mgmt-port" = {
          matchConfig.Name = mgmtVlanIf;
          networkConfig = {
            Bridge = "br-mgmt";
            DHCP = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
        };
      }

      #
      # br-mgmt = DHCP client
      #
      {
        "06-br-mgmt" = {
          matchConfig.Name = "br-mgmt";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
            BindCarrier = [ mgmtVlanIf ];
          };
          linkConfig.RequiredForOnline = false;
        };
      }

      #
      # Fabric trunk physical port
      #
      {
        "10-trunk-port" = {
          matchConfig.Name = trunkParent;
          networkConfig = {
            Bridge = uplinkBridge;
            DHCP = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;

            VLAN = allVlansOnTrunk;
          };
        };
      }

      #
      # Uplink bridge
      #
      {
        "11-uplink-bridge" = {
          matchConfig.Name = uplinkBridge;
          networkConfig.ConfigureWithoutCarrier = true;
        };
      }
    ]

    #
    # Bring up each LAN bridge
    #
    ++ map (vid: {
      "12-${lanBridgeFor vid}" = {
        matchConfig.Name = lanBridgeFor vid;
        networkConfig.ConfigureWithoutCarrier = true;
      };
    }) tenantVlans

    #
    # Bring up each transit bridge
    #
    ++ map (vid: {
      "20-${transitBridgeFor vid}" = {
        matchConfig.Name = transitBridgeFor vid;
        networkConfig.ConfigureWithoutCarrier = true;
      };
    }) tenantVlans

    #
    # Bridge eth0.<LANVID> → br-lan-<LANVID>
    #
    ++ map (vid: {
      "30-port-${lanVlanIfFor vid}" = {
        matchConfig.Name = lanVlanIfFor vid;
        networkConfig = {
          Bridge = lanBridgeFor vid;
          DHCP = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
      };
    }) tenantVlans

    #
    # Bridge eth0.<TRANSITVID> → tr<TRANSITVID>
    #
    ++ map (vid: {
      "31-port-${transitVlanIfFor vid}" = {
        matchConfig.Name = transitVlanIfFor vid;
        networkConfig = {
          Bridge = transitBridgeFor vid;
          DHCP = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
      };
    }) tenantVlans
  );
}
