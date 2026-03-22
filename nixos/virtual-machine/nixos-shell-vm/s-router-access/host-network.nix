# ./host-network/network.nix
{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  mkMgmt = import "${outPath}/library/10-vms/nixos-shell-vm/1-helpers/mk-management-networkd.nix" {
    inherit lib pkgs;
  };

  trunkParent = "eth0";

  tenantVlans = [ 10 15 20 ];
  policyBase = 100;

  transitVidFor = vid: policyBase + vid;

  lanBridgeFor = vid: "br-lan-${toString vid}";
  lanVlanIfFor = vid: "${trunkParent}.${toString vid}";

  transitBridgeFor = vid: "br-tr-${toString vid}";
  transitVlanIfFor = vid: "${trunkParent}.${toString (transitVidFor vid)}";

in
{
  imports = [
    (mkMgmt "eth0" 2 { bridge = "vlan2"; })
  ];

  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.netdevs =
    lib.mkMerge (
      (map (vid: {
        "10-${lanBridgeFor vid}" = {
          netdevConfig = {
            Name = lanBridgeFor vid;
            Kind = "bridge";
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "11-${transitBridgeFor vid}" = {
          netdevConfig = {
            Name = transitBridgeFor vid;
            Kind = "bridge";
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "20-${lanVlanIfFor vid}" = {
          netdevConfig = {
            Name = lanVlanIfFor vid;
            Kind = "vlan";
          };
          vlanConfig.Id = vid;
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "21-${transitVlanIfFor vid}" = {
          netdevConfig = {
            Name = transitVlanIfFor vid;
            Kind = "vlan";
          };
          vlanConfig.Id = transitVidFor vid;
        };
      }) tenantVlans)
    );

  systemd.network.networks =
    lib.mkMerge (
      [
        {
          "00-${trunkParent}" = {
            matchConfig.Name = trunkParent;
            networkConfig = {
              VLAN = map lanVlanIfFor tenantVlans
                   ++ map transitVlanIfFor tenantVlans;
              ConfigureWithoutCarrier = true;
            };
          };
        }
      ]
      ++
      (map (vid: {
        "30-${lanVlanIfFor vid}" = {
          matchConfig.Name = lanVlanIfFor vid;
          networkConfig = {
            Bridge = lanBridgeFor vid;
            ConfigureWithoutCarrier = true;
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "31-${transitVlanIfFor vid}" = {
          matchConfig.Name = transitVlanIfFor vid;
          networkConfig = {
            Bridge = transitBridgeFor vid;
            ConfigureWithoutCarrier = true;
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "40-${lanBridgeFor vid}" = {
          matchConfig.Name = lanBridgeFor vid;
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
        };
      }) tenantVlans)
      ++
      (map (vid: {
        "41-${transitBridgeFor vid}" = {
          matchConfig.Name = transitBridgeFor vid;
          networkConfig = {
            ConfigureWithoutCarrier = true;
          };
        };
      }) tenantVlans)
    );
}
