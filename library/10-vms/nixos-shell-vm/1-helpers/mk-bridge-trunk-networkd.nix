{ lib, pkgs }:

parent: opts:

{
  config,
  lib,
  pkgs,
  ...
}:

let
  bridge = opts.bridge;
in
{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkDefault false;

  # Do not wait on the trunk
  systemd.services.systemd-networkd-wait-online = {
    serviceConfig.ExecStart = lib.mkDefault (
      "${config.systemd.package}/lib/systemd/systemd-networkd-wait-online --ignore=${parent}"
    );
  };

  systemd.network = {
    enable = true;

    # Only a bridge, no VLANs
    netdevs = {
      "10-${bridge}" = {
        netdevConfig = {
          Name = bridge;
          Kind = "bridge";
        };
      };
    };

    networks = {
      # Physical NIC → bridge
      "10-${parent}" = {
        matchConfig.Name = parent;
        networkConfig = {
          Bridge = bridge;
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
      };

      # Bridge itself (pure L2)
      "20-${bridge}" = {
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
