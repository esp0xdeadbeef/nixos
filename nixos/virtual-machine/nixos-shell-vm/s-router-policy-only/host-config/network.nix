{
  outPath,
  lib,
  pkgs,
  ...
}:

let
  cfg = import "${outPath}/library/100-fabric-routing/inputs/intent.nix";

  tenantVlans =
    if cfg ? tenantVlans then
      cfg.tenantVlans
    else
      [ 10 20 30 40 50 60 70 80 ];

  policyBase =
    if cfg ? policyAccessTransitBase then
      cfg.policyAccessTransitBase
    else
      100;

  transitVidFor = vid: policyBase + vid;

in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = lib.mkMerge (
    [
      {
        "05-br-mgmt".netdevConfig = {
          Name = "br-mgmt";
          Kind = "bridge";
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

  systemd.network.networks = lib.mkMerge (
    [
      {
        "05-mgmt-port" = {
          matchConfig.Name = "eth1";
          networkConfig = {
            Bridge = "br-mgmt";
            DHCP = "no";
            IPv6AcceptRA = false;
            ConfigureWithoutCarrier = true;
          };
        };
      }

      {
        "06-br-mgmt" = {
          matchConfig.Name = "br-mgmt";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = true;
            ConfigureWithoutCarrier = true;
          };
        };
      }

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
