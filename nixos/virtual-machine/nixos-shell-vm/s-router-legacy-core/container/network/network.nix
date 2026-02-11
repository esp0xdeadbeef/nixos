{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "lan";
  wanIf = "wan";

  natVlans = [ 1010 ]; # builtins.genList (i: i + 1010) 1; # 1010
  wanVlan = 6;
in
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  systemd.network.netdevs =
    lib.genAttrs (map (v: "10-${lanIf}-vlan${toString v}") natVlans) (
      v:
      let
        id = lib.toInt (lib.last (lib.splitString "vlan" v));
      in
      {
        netdevConfig = {
          Name = "${lanIf}.${toString id}";
          Kind = "vlan";
        };
        vlanConfig.Id = id;
      }
    )
    // lib.genAttrs (map (v: "20-br-vlan${toString v}") natVlans) (
      v:
      let
        id = lib.toInt (lib.last (lib.splitString "vlan" v));
      in
      {
        netdevConfig = {
          Name = "br-vlan${toString id}";
          Kind = "bridge";
        };
      }
    )
    // {
      "10-${wanIf}-vlan${toString wanVlan}" = {
        netdevConfig = {
          Name = "${wanIf}.${toString wanVlan}";
          Kind = "vlan";
        };
        vlanConfig.Id = wanVlan;
      };

      "20-br-wan${toString wanVlan}" = {
        netdevConfig = {
          Name = "br-wan${toString wanVlan}";
          Kind = "bridge";
        };
      };
    };

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

    "40-${wanIf}" = {
      matchConfig.Name = wanIf;
      networkConfig = {
        DHCP = "no";
        IPv6AcceptRA = false;
        LinkLocalAddressing = "no";
        VLAN = [ "${wanIf}.${toString wanVlan}" ];
      };
    };

    "50-${wanIf}.${toString wanVlan}" = {
      matchConfig.Name = "${wanIf}.${toString wanVlan}";
      networkConfig.Bridge = "br-wan${toString wanVlan}";
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
      networkConfig.ConfigureWithoutCarrier = true;
    }
  )
  // {
    "60-br-wan${toString wanVlan}" = {
      matchConfig.Name = "br-wan${toString wanVlan}";
      networkConfig.ConfigureWithoutCarrier = true;
    };
  };
}
