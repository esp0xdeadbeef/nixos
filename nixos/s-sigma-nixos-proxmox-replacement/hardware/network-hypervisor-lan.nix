{ config, pkgs, lib, ... }:

let
  lanIf = "ens21";
  natVlans = [ 2 ];
in
{
  systemd.network.netdevs =
    lib.genAttrs (map (v: "10-${lanIf}-vlan${toString v}") natVlans) (name:
      let
        v = lib.toInt (lib.last (lib.splitString "vlan" name));
      in {
        netdevConfig = {
          Name = "${lanIf}.${toString v}";
          Kind = "vlan";
        };
        vlanConfig.Id = v;
      }
    )
    //
    lib.genAttrs (map (v: "20-br-vlan${toString v}") natVlans) (name:
      let
        v = lib.toInt (lib.last (lib.splitString "vlan" name));
      in {
        netdevConfig = {
          Name = "br-vlan${toString v}";
          Kind = "bridge";
        };
      }
    );

  ########################################
  # NETWORKS
  ########################################
  systemd.network.networks =
    {
      "20-${lanIf}" = {
        matchConfig.Name = lanIf;
        networkConfig = {
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
          VLAN = map (v: "${lanIf}.${toString v}") natVlans;
        };
      };
    }
    //
    lib.genAttrs (map (v: "30-${lanIf}.${toString v}") natVlans) (name:
      let
        v = lib.toInt (lib.last (lib.splitString "." name));
      in {
        matchConfig.Name = "${lanIf}.${toString v}";
        networkConfig.Bridge = "br-vlan${toString v}";
      }
    )
    //
    lib.genAttrs (map (v: "60-br-vlan${toString v}") natVlans) (name:
      let
        v = lib.toInt (lib.last (lib.splitString "vlan" name));
      in {
        matchConfig.Name = "br-vlan${toString v}";
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCP = "no";
          IPv6AcceptRA = false;
          LinkLocalAddressing = "no";
        };
      }
    );
}
