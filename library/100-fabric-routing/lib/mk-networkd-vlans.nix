# lib/mk-networkd-vlans.nix
{ lib, topo }:

let
  mkVlanIf = base: vid: "${base}.${toString vid}";
  transitBridgeNameFor = vid: "br-transit${toString vid}";
in
{
  lanIf,
  wanIf,
  transitVlans ? [ ],
  wanVlan,
}:

{
  ############################
  # NETDEVS
  ############################
  netdevs = lib.mkMerge (

    # transit VLANs ONLY
    (map (vid: {
      "lan-vlan-${toString vid}" = {
        netdevConfig = {
          Name = mkVlanIf lanIf vid;
          Kind = "vlan";
        };
        vlanConfig.Id = vid;
      };

      "br-transit-${toString vid}" = {
        netdevConfig = {
          Name = transitBridgeNameFor vid;
          Kind = "bridge";
        };
      };
    }) transitVlans)

    # wan VLAN
    ++ [
      {
        "wan-vlan-${toString wanVlan}" = {
          netdevConfig = {
            Name = mkVlanIf wanIf wanVlan;
            Kind = "vlan";
          };
          vlanConfig.Id = wanVlan;
        };

        "br-wan${toString wanVlan}" = {
          netdevConfig = {
            Name = "br-wan${toString wanVlan}";
            Kind = "bridge";
          };
        };
      }
    ]
  );

  ############################
  # NETWORKS
  ############################
  networks = lib.mkMerge (

    # attach transit VLANs to lan
    (map (vid: {
      "10-${lanIf}-transit-vlan-${toString vid}" = {
        matchConfig.Name = lanIf;
        networkConfig.VLAN = [ (mkVlanIf lanIf vid) ];
      };

      "20-lan-transit-${toString vid}" = {
        matchConfig.Name = mkVlanIf lanIf vid;
        networkConfig.Bridge = transitBridgeNameFor vid;
      };

      "30-br-transit-${toString vid}" = {
        matchConfig.Name = transitBridgeNameFor vid;
        networkConfig = {
          ConfigureWithoutCarrier = true;
          IPv6AcceptRA = false;
          IPv6Forwarding = true;
        };
      };
    }) transitVlans)

    # wan wiring
    ++ [
      {
        "40-${wanIf}-vlan" = {
          matchConfig.Name = wanIf;
          networkConfig.VLAN = [ (mkVlanIf wanIf wanVlan) ];
        };

        "50-wan-vlan" = {
          matchConfig.Name = mkVlanIf wanIf wanVlan;
          networkConfig.Bridge = "br-wan${toString wanVlan}";
        };

        "60-br-wan" = {
          matchConfig.Name = "br-wan${toString wanVlan}";
          networkConfig.ConfigureWithoutCarrier = true;
        };
      }
    ]
  );
}
