{ lib, ... }:

{
  # The cobalt router VM owns the USB (WAN) and dock (LAN trunk) NICs. Leave
  # NetworkManager in charge of Wi-Fi, but take these two wired interfaces out
  # of NM so systemd-networkd can enslave them into pure L2 bridges.
  networking.networkmanager.unmanaged = [
    "enp170s0"
    "wan0"
    "br-cobalt-lan"
    "br-cobalt-wan"
  ];

  # The USB NIC's bus path renumbers across replugs (enp0s13f0u4u4u3 ->
  # enp0s13f0u3u1 ...), which broke the bridge. Pin it by its USB product
  # identity (Linksys USB3GIGV1) to a stable name so the cobalt WAN bridge
  # survives replugs/reboots.
  systemd.network.links."10-wan0" = {
    matchConfig.Property = "ID_VENDOR_ID=13b1 ID_MODEL_ID=0041";
    linkConfig.Name = "wan0";
  };

  systemd.network.enable = true;

  # The networkd + NM own the NICs; the global scripted DHCP client only
  # fights them (and would DHCP on the cobalt's WAN USB). Disable it.
  networking.useDHCP = lib.mkForce false;

  # The cobalt bridges are pure L2 (no host IP) and l-envil's only real
  # uplink is Wi-Fi (NetworkManager). The networkd wait-online has nothing
  # meaningful to wait for, so do not let it block the host switch.
  systemd.network.wait-online.enable = false;

  systemd.services.NetworkManager-wait-online.enable = false;

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
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "br-cobalt-lan";
    };

    "10-wan0" = {
      matchConfig.Name = "wan0";
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "br-cobalt-wan";
    };

    "10-br-cobalt-lan" = {
      matchConfig.Name = "br-cobalt-lan";
      linkConfig.RequiredForOnline = "no";
      networkConfig = { };
    };

    "10-br-cobalt-wan" = {
      matchConfig.Name = "br-cobalt-wan";
      linkConfig.RequiredForOnline = "no";
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
