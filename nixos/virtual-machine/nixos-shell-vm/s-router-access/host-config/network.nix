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
      # mgmt VLAN subinterface
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

      {
        "10-br-lan-trunk".netdevConfig = {
          Name = "br-lan-trunk";
          Kind = "bridge";
        };
      }
    ]
    ++ map (vid: {
      "20-tr${toString (transitVidFor vid)}".netdevConfig = {
        Name = "tr${toString (transitVidFor vid)}";
        Kind = "bridge";
      };
    }) tenantVlans
  );

  ############################
  # NETWORKS
  ############################
  systemd.network.networks = lib.mkMerge (

    [
      #
      # Parent mgmt NIC: instantiate VLAN(s) only
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
      # VLAN mgmt NIC → bridge ONLY
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
      # Mgmt bridge = DHCPv4 CLIENT
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
          linkConfig = {
            RequiredForOnline = false;
          };
        };
      }

      #
      # Fabric trunk
      #
      {
        "10-trunk-port" = {
          matchConfig.Name = "eth0";
          networkConfig = {
            Bridge = "br-lan-trunk";
            DHCP = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
        };
      }

      {
        "11-br-lan-trunk" = {
          matchConfig.Name = "br-lan-trunk";
          networkConfig.ConfigureWithoutCarrier = true;
        };
      }
    ]

    ++ map (vid: {
      "30-tr${toString (transitVidFor vid)}" = {
        matchConfig.Name = "tr${toString (transitVidFor vid)}";
        networkConfig.ConfigureWithoutCarrier = true;
      };
    }) tenantVlans
  );
}

