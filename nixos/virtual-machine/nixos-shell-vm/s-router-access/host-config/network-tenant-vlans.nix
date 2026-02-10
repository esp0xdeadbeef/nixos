# FILE: ./host-config/network-tenant-vlans.nix
{ lib, config, ... }:

let
  tenantVlans =
    if config ? routerAccess && config.routerAccess ? tenantVlans then
      config.routerAccess.tenantVlans
    else if config ? fabricInputs && config.fabricInputs ? tenantVlans then
      config.fabricInputs.tenantVlans
    else
      [ 10 20 30 40 50 60 70 80 ];

  # FIX: VLAN trunk is eth0, not eth1
  uplinkIf = "eth1";

  vlanIf = vid: "${uplinkIf}.${toString vid}";
  bridge = vid: "lan${toString vid}";

  mkVlan =
    vid: {
      netdevs = {
        "${vlanIf vid}" = {
          netdevConfig = {
            Name = vlanIf vid;
            Kind = "vlan";
          };
          vlanConfig.Id = vid;
        };
      };

      networks = {
        "10-${vlanIf vid}" = {
          matchConfig.Name = vlanIf vid;
          networkConfig = {
            Bridge = lib.mkForce (bridge vid);
            ConfigureWithoutCarrier = true;
          };
        };
      };
    };

  vlanFragments = map mkVlan tenantVlans;

in
{
  # Attach VLAN subinterfaces to eth0
  systemd.network.networks =
    lib.mkMerge (
      [
        {
          "05-${uplinkIf}-trunk" = {
            matchConfig.Name = uplinkIf;
            networkConfig = {
              DHCP = "no";
              VLAN = map (vid: vlanIf vid) tenantVlans;
            };
          };
        }
      ]
      ++ map (f: f.networks) vlanFragments
    );

  systemd.network.netdevs =
    lib.mkMerge (map (f: f.netdevs) vlanFragments);
}

