# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/host-config/network.nix
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

  trunkBridge = "br-lan-trunk";
  trunkParent = "eth0";

  # FIX: transit VLANs live on the PHYSICAL trunk NIC, not on the bridge
  trunkTransitVlanIf = tvid: "${trunkParent}.${toString tvid}";
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
      # Mgmt VLAN (correct, keep as-is)
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

      {
        "05-br-mgmt".netdevConfig = {
          Name = "br-mgmt";
          Kind = "bridge";
        };
        "05-br-mgmt".bridgeConfig = {
          STP = false;
          ForwardDelaySec = 0;
        };
      }

      #
      # Fabric trunk bridge
      #
      {
        "10-br-lan-trunk".netdevConfig = {
          Name = trunkBridge;
          Kind = "bridge";
        };
      }
    ]

    #
    # Per-tenant transit bridges (containers attach here)
    #
    ++ map (vid: {
      "20-tr${toString (transitVidFor vid)}".netdevConfig = {
        Name = "tr${toString (transitVidFor vid)}";
        Kind = "bridge";
      };
    }) tenantVlans

    #
    # FIX: VLAN subinterfaces on *eth0* (eth0.<VID>)
    #
    ++ map (vid: {
      "21-${trunkTransitVlanIf (transitVidFor vid)}" = {
        netdevConfig = {
          Name = trunkTransitVlanIf (transitVidFor vid);
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
      # Mgmt VLAN → bridge
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
      # Mgmt bridge = DHCP client
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
      # FIX: instantiate ALL transit VLANs here
      #
      {
        "10-trunk-port" = {
          matchConfig.Name = trunkParent;
          networkConfig = {
            Bridge = trunkBridge;
            DHCP = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;

            VLAN = map (vid: trunkTransitVlanIf (transitVidFor vid)) tenantVlans;
          };
        };
      }

      {
        "11-br-lan-trunk" = {
          matchConfig.Name = trunkBridge;
          networkConfig.ConfigureWithoutCarrier = true;
        };
      }
    ]

    #
    # Bring up each per-tenant transit bridge
    #
    ++ map (vid: {
      "30-tr${toString (transitVidFor vid)}" = {
        matchConfig.Name = "tr${toString (transitVidFor vid)}";
        networkConfig.ConfigureWithoutCarrier = true;
      };
    }) tenantVlans

    #
    # FIX: bridge eth0.<VID> into tr<VID>
    #
    ++ map (vid: {
      "41-port-${trunkTransitVlanIf (transitVidFor vid)}" = {
        matchConfig.Name = trunkTransitVlanIf (transitVidFor vid);
        networkConfig = {
          Bridge = "tr${toString (transitVidFor vid)}";
          DHCP = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
      };
    }) tenantVlans
  );
}

