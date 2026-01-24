{ lib, pkgs }:

parent: vlanId: opts:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  vlan = "${parent}.${toString vlanId}";
  bridge = opts.bridge or null;
in
{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkDefault false;

  systemd.services.systemd-networkd-wait-online = {
    serviceConfig.ExecStart = lib.mkDefault (
      "${config.systemd.package}/lib/systemd/systemd-networkd-wait-online --ignore=${parent}"
    );
  };

  systemd.network = {
    enable = true;

    netdevs = {
      "10-${parent}-vlan${toString vlanId}" = {
        netdevConfig = {
          Name = vlan;
          Kind = "vlan";
        };
        vlanConfig.Id = vlanId;
      };
    }
    // lib.optionalAttrs (bridge != null) {
      "10-${bridge}" = {
        netdevConfig = {
          Name = bridge;
          Kind = "bridge";
        };
      };
    };

    networks = {
      "10-${parent}" = {
        matchConfig.Name = parent;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
          VLAN = [ vlan ];
        };
      };

      "20-${vlan}" = {
        matchConfig.Name = vlan;
        networkConfig = {
          LinkLocalAddressing = "no";
        }
        // lib.optionalAttrs (bridge != null) {
          Bridge = bridge;
        }
        // lib.optionalAttrs (bridge == null) {
          DHCP = "ipv4";
        };
      };
    }
    // lib.optionalAttrs (bridge != null) {
      "30-${bridge}" = {
        matchConfig.Name = bridge;
        networkConfig = {
          ConfigureWithoutCarrier = true;
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };
    };
  };
}
