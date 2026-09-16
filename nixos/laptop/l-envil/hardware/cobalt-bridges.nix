{ lib, ... }:

{
  # l-envil exposes the cobalt router's physical WAN and LAN trunk through two
  # hot-pluggable NICs. Both of them re-enumerate onto a different PCI bus after
  # a dock/cage hotplug or power event, so their kernel names drift between
  # boots (observed for the same hardware: enp170s0, enp0s13f0u3u2, enp128s0 on
  # the dock side; ens1f0, enp131s0f0 on the SFP+ cage). Referencing any kernel
  # name here would silently drop the NIC out of its bridge and need a manual
  # `ip link set ... master`.
  #
  # Bind instead by the NIC's permanent (burned-in) MAC — the "physical NIC
  # identity" space — to a role-named runtime interface (URS/FS-188), and let
  # every rule below reference only that stable name. This is a host-side
  # platform binding of realization mechanics; it adds no network meaning
  # (FS-176, FS-187).
  systemd.network.enable = true;

  systemd.network.links = {
    # Dock LAN trunk NIC: Intel I225-LMvP behind the ThinkPad Thunderbolt 4
    # Dock. Carries the switch trunk into br-cobalt-lan.
    "10-cobalt-lan0" = {
      matchConfig.PermanentMACAddress = "08:3a:88:c2:d2:c0";
      linkConfig.Name = "cobalt-lan0";
    };

    # SFP+ WAN NIC: Intel 82599ES port 0 in the DM7801BJ Thunderbolt cage
    # (FRITZ!SFP XGS-PON). Carries the ISP uplink into br-cobalt-wan. Only
    # port 0 (MAC ...:b0:dd) is pinned; the cage's second port (MAC ...:b0:de)
    # is unused and stays on its kernel name.
    "10-cobalt-wan0" = {
      matchConfig.PermanentMACAddress = "00:1b:21:ba:b0:dd";
      linkConfig.Name = "cobalt-wan0";
    };
  };

  # NetworkManager owns Wi-Fi only. Keep the two wired NICs (under their pinned
  # names) and the bridges out of NM so systemd-networkd can enslave them into
  # pure L2 bridges. The derived VLAN 30 bridge is host-addressed, but NM must
  # still keep its hands off it so it does not fight networkd for the address.
  networking.networkmanager.unmanaged = [
    "cobalt-lan0"
    "cobalt-wan0"
    "br-cobalt-lan"
    "br-cobalt-wan"
    "br-cobalt-lan.30"
    "vlan30"
  ];

  # The networkd + NM own the NICs; the global scripted DHCP client only
  # fights them (and would DHCP on the cobalt's WAN). Disable it.
  networking.useDHCP = lib.mkForce false;

  # The cobalt bridges are pure L2 (no host IP) and the host reaches the
  # clients plane over the dock trunk without Wi-Fi. The networkd wait-online
  # has nothing meaningful to wait for, so do not let it block the host switch.
  systemd.network.wait-online.enable = false;

  systemd.services.NetworkManager-wait-online.enable = false;

  # Pure L2 bridges for the cobalt VM: no IP on the host. The cobalt VM owns
  # all addressing on the trunk (VLAN 300 tagged DHCP on the WAN side, LAN
  # trunk on the dock side).
  #
  # In addition, expose the clients plane (VLAN 30) to the host itself so
  # l-envil has a wired clients-plane path and no longer needs Wi-Fi for it.
  # The dock trunk (switch port 3) carries VLAN 30 tagged, so derive a VLAN 30
  # interface from br-cobalt-lan, terminate the 802.1Q tag, and hand the
  # resulting untagged segment to the host through the `vlan30` bridge (same
  # shape as `mkBridge <parent> 30 { bridge = "vlan30"; }`). The host takes a
  # DHCP lease on that bridge.
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

    "20-br-cobalt-lan.30" = {
      netdevConfig = {
        Name = "br-cobalt-lan.30";
        Kind = "vlan";
      };
      vlanConfig.Id = 30;
    };

    "20-vlan30" = {
      netdevConfig = {
        Name = "vlan30";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = {
    "10-cobalt-lan0" = {
      matchConfig.Name = "cobalt-lan0";
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "br-cobalt-lan";
    };

    "10-cobalt-wan0" = {
      matchConfig.Name = "cobalt-wan0";
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "br-cobalt-wan";
    };

    "10-br-cobalt-lan" = {
      matchConfig.Name = "br-cobalt-lan";
      linkConfig.RequiredForOnline = "no";
      # Terminate VLAN 30 off the dock trunk; the VLAN child is bridged to the
      # untagged `vlan30` bridge below.
      networkConfig.VLAN = [ "br-cobalt-lan.30" ];
    };

    "10-br-cobalt-wan" = {
      matchConfig.Name = "br-cobalt-wan";
      linkConfig.RequiredForOnline = "no";
      networkConfig = { };
    };

    # VLAN 30 child of the LAN trunk -> untagged clients bridge.
    "20-br-cobalt-lan.30" = {
      matchConfig.Name = "br-cobalt-lan.30";
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "vlan30";
    };

    # Untagged VLAN 30 bridge. l-envil takes its clients-plane address here
    # (DHCP), so the wired dock is a Wi-Fi-free path to VLAN 30.
    "20-vlan30" = {
      matchConfig.Name = "vlan30";
      linkConfig.RequiredForOnline = "no";
      networkConfig = {
        DHCP = "ipv4";
        LinkLocalAddressing = "no";
      };
    };
  };

  virtualisation.libvirtd = {
    enable = true;
    allowedBridges = [
      "br-cobalt-lan"
      "br-cobalt-wan"
      "vlan30"
    ];
  };

  networking.firewall.checkReversePath = false;
}
