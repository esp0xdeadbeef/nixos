{ lib, pkgs }:

parent: vlanId: opts:

{ config
, lib
, pkgs
, ...
}:

let
  id = toString vlanId;

  # VLAN subinterface on the parent NIC (eth0.2, eth0.6, ...)
  vlanIf = "${parent}.${id}";

  # Bridge name: MUST match what your container uses (hostBridge = "vlan2")
  bridge = opts.bridge or "vlan${id}";

  # Whether the host should DHCP on the bridge (Proxmox-style)
  hostDHCP = opts.hostDHCP or true;

  # Whether the host should accept IPv6 RA/SLAAC on the bridge.
  hostSLAAC = opts.hostSLAAC or true;

  # Convenience: systemd-networkd expects strings like "no"/"ipv4"/"ipv6"
  noLinkLocal = "no";
in
{
  networking.useNetworkd = true;
  networking.useDHCP = false;
  networking.networkmanager.enable = lib.mkDefault false;

  # Avoid wait-online getting stuck on raw parent links
  systemd.services.systemd-networkd-wait-online = {
    serviceConfig.ExecStart = lib.mkDefault "${config.systemd.package}/lib/systemd/systemd-networkd-wait-online --ignore=${parent}";
  };

  systemd.network = {
    enable = true;

    netdevs = {
      # VLAN device (eth0.2)
      "10-${vlanIf}" = {
        netdevConfig = {
          Name = vlanIf;
          Kind = "vlan";
        };
        vlanConfig = {
          Id = vlanId;
        };
      };

      # Bridge device (vlan2) -- Proxmox vmbr equivalent
      "20-${bridge}" = {
        netdevConfig = {
          Name = bridge;
          Kind = "bridge";
        };
      };
    };

    networks = {
      # Parent interface: no L3, just creates/attaches VLAN subif
      "10-${parent}" = {
        matchConfig.Name = parent;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = noLinkLocal;
          VLAN = [ vlanIf ];
        };
      };

      # VLAN subif: NO IP here; it is a bridge port
      "20-${vlanIf}" = {
        matchConfig.Name = vlanIf;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = noLinkLocal;

          # enslave VLAN link into bridge
          Bridge = bridge;
        };
      };

      # Bridge: host gets DHCP here (and containers can too)
      "30-${bridge}" = {
        matchConfig.Name = bridge;
        networkConfig = {
          DHCP = if hostDHCP then "ipv4" else "no";
          LinkLocalAddressing = if hostSLAAC then "ipv6" else noLinkLocal;
          IPv6AcceptRA = if hostSLAAC then "yes" else "no";
        };
      };
    };
  };
}
