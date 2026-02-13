# ./host-network.nix
# FILE: s-router-core/host-network.nix
{
  fabricInputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = fabricInputs;

  tenantVlans = cfg.tenantVlans;

  # Core router does NOT use access transit offsets
  trunkParent = "eth0";

  mgmtParent = "eth1";
  mgmtVlanId = 2;
  mgmtVlanIf = "${mgmtParent}.${toString mgmtVlanId}";

  uplinkBridge = "br-lan-trunk";

  lanBridgeFor = vid: "br-lan-${toString vid}";
  lanVlanIfFor = vid: "${trunkParent}.${toString vid}";

  allVlansOnTrunk = map lanVlanIfFor tenantVlans;
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  ############################################################
  # NETDEVS
  ############################################################
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
      # Fabric trunk bridge
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
    # Per-tenant LAN bridges ONLY (no transit bridges on core)
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
  );

  ############################################################
  # NETWORKS
  ############################################################
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
    # Bridge eth0.<VID> → br-lan-<VID>
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
  );
}

