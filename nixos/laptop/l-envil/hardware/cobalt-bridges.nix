{ lib, ... }:

{
  # The cobalt router VM owns the USB (WAN) and dock (LAN trunk) NICs. Leave
  # NetworkManager in charge of Wi-Fi, but take these two wired interfaces out
  # of NM so systemd-networkd can enslave them into pure L2 bridges.
  networking.networkmanager.unmanaged = [
    "enp170s0"
    "enp0s13f0u4u4u3"
    "br-cobalt-lan"
    "br-cobalt-wan"
  ];

  systemd.network.enable = true;

  # The cobalt bridges are pure L2 (no host IP), so they never become
  # "online". Succeed once any real interface (Wi-Fi) is online instead.
  systemd.network.wait-online = {
    anyInterface = true;
    ignoredInterfaces = [
      "br-cobalt-lan"
      "br-cobalt-wan"
    ];
  };

  # Pure L2 bridges: no IP on the host. The cobalt VM owns all addressing
  # (VLAN 300 tagged DHCP on the WAN side, LAN trunk on the dock side).
  systemd.network.netdevs = {
    "10-br-cobalt-lan" = {
      netdevConfig = {
        Name = "br-cobalt-lan";
        Kind = "bridge";
      };
    };

    "10-br-cobalt-wan" = {
      netdevConfig = {
        Name = "br-cobalt-wan";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    "10-enp170s0" = {
      matchConfig.Name = "enp170s0";
      networkConfig.Bridge = "br-cobalt-lan";
    };

    "10-enp0s13f0u4u4u3" = {
      matchConfig.Name = "enp0s13f0u4u4u3";
      networkConfig.Bridge = "br-cobalt-wan";
    };

    "10-br-cobalt-lan" = {
      matchConfig.Name = "br-cobalt-lan";
      networkConfig = { };
      vlan = [ "unlock-vlan" ];
    };

    "10-br-cobalt-wan" = {
      matchConfig.Name = "br-cobalt-wan";
      networkConfig = { };
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = [
      "br-cobalt-lan"
      "br-cobalt-wan"
    ];
  };

  networking.firewall.checkReversePath = false;
}
