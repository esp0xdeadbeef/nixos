# /home/deadbeef/github/nixos/nixos/virtual-machine/nixos-shell-vm/s-router-access/host-config/network-tenant-vlans.nix
# FILE: s-router-access/host-config/network-tenant-vlans.nix
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

  trunkBridge = "br-lan-trunk";
  trunkParent = "eth0";

  trunkTransitVlanIf = tvid: "${trunkBridge}.${toString tvid}";
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = lib.mkMerge (
    [
      {
        "10-br-lan-trunk".netdevConfig = {
          Name = trunkBridge;
          Kind = "bridge";
        };
      }
    ]
    # per-tenant transit bridges
    ++ map (vid: {
      "20-tr${toString (transitVidFor vid)}".netdevConfig = {
        Name = "tr${toString (transitVidFor vid)}";
        Kind = "bridge";
      };
    }) tenantVlans

    # VLAN subinterfaces on top of trunk bridge for each transit VLAN
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

  systemd.network.networks = lib.mkMerge (
    [
      {
        "10-trunk-port" = {
          matchConfig.Name = trunkParent;
          networkConfig = {
            Bridge = trunkBridge;
            DHCP = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
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

    # transit bridges up
    ++ map (vid: {
      "30-tr${toString (transitVidFor vid)}" = {
        matchConfig.Name = "tr${toString (transitVidFor vid)}";
        networkConfig.ConfigureWithoutCarrier = true;
      };
    }) tenantVlans

    # trunk bridge spawns VLAN netdevs; each VLAN netdev is bridged into tr<VID>
    ++ map (vid: {
      "40-${trunkBridge}-vlan-${toString (transitVidFor vid)}" = {
        matchConfig.Name = trunkBridge;
        networkConfig = {
          VLAN = [ (trunkTransitVlanIf (transitVidFor vid)) ];
          DHCP = "no";
          IPv6AcceptRA = false;
          ConfigureWithoutCarrier = true;
        };
      };

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

