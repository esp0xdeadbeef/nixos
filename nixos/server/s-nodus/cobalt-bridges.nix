{ lib, pkgs, ... }:

# Cobalt host-side platform binding for the s-router-cobalt-new VM
# (Banana Pi BPI-R4 Pro 4E).
#
# Role (mirrors nixos/laptop/l-envil/hardware/cobalt-bridges.nix):
#   mxl_lan0 -> 802.1Q trunk into br-cobalt-lan (carries the cobalt LAN trunk)
#   mxl_lan1 -> access port, untagged (VLAN 30)  (clients)
#   mxl_lan2 -> access port, untagged (VLAN 50)  (cobalt-iot; lab/OSEE bench)
#   lan5     -> management (DHCP, host uplink/nebula) -- NOT part of the bridges
#   sfp1/sfp2 -> SFP+ cages; sfp2 is the WAN source for VM activation
#
# VLAN 50 is `cobalt-iot`: one of the tenants the intent grants
# `allowTenantToWan` (prio 120), so a device on mxl_lan2 gets DHCP from the
# cobalt router AND Internet egress, on its own subnet (10.2.50.0/24) rather
# than sharing VLAN 30 with this host (10.2.30.100) and the AP clients.
#
# This binds realization mechanics (which physical port carries which role,
# runtime interface names, bridge/IPAM plumbing).  It adds no network meaning:
# trunk/VLAN/service semantics live in the canonical realization bundle the VM
# consumes (FS-176, FS-187; URS "platform binding").
#
# The board has TWO switch chips; ./lan-port-map.nix is the single source of
# truth for every real jack (MT7988 internal ports 0/2/3 and the MxL86252
# 2.5G ports), and the DT overlay and these networkd rules are generated from
# the SAME map.  Notably there is NO `lan1`: on the 4E the MT7988 internal
# switch port 1 has a PHY/LED but no jack, so it is deleted rather than
# exposed as a fake interface.
let
  # Single source of truth for the Ethernet port map (DT label + role).
  portMap = import ./lan-port-map.nix { inherit lib; };

  # VLANs the host terminates off the trunk for its untagged access ports.
  #
  #   clientsVlan = cobalt-clients (30): the host's own management/underlay
  #                 rides here as DHCP (see the vlan30 rule below), and
  #                 mxl_lan1 is the original access jack.
  #   iotVlan     = cobalt-iot (50): mxl_lan2's bench plane.  Kept separate
  #                 from clients so lab traffic cannot reach this host's own
  #                 management address or the AP clients L2.
  #
  # Both are `allowTenantToWan` tenants, so both egress to the Internet.
  clientsVlan = 30;
  iotVlan = 50;

  # Every VLAN the host must terminate from the trunk (child netdev + bridge).
  accessVlans = [ clientsVlan iotVlan ];

  # The bridge an access port joins for its VLAN.
  accessBridge = vlan: "vlan${toString vlan}";

  # networkd `.network` stanza for one mapped port, keyed by its DT label.
  #   trunk      -> 802.1Q trunk into br-cobalt-lan
  #   access     -> untagged VLAN into that VLAN's access bridge (p.vlan)
  #   unused     -> realized netdev, no bridge (jack present, no cobalt role)
  #   management -> a plain, unaddressed jack.  The host's own management/
  #                 underlay no longer rides a dedicated physical jack: it now
  #                 comes off the trunk as tagged VLAN 30 (see the vlan30 DHCP
  #                 rule below), so it survives losing/moving the mgmt cable.
  mkPortNetwork = p:
    if p.role == "management" || p.role == "unused" then
      lib.nameValuePair "10-${p.label}"
        {
          matchConfig.Name = p.label;
          linkConfig.RequiredForOnline = "no";
          # An `unused` jack is realized but deliberately inert: no bridge, no
          # address.  It must not carry a `Bridge=` key at all -- emitting one
          # under `mkIf false` still leaves a dangling directive in the unit.
          networkConfig = { };
        }
    else
      lib.nameValuePair "10-${p.label}" {
        matchConfig.Name = p.label;
        linkConfig.RequiredForOnline = "no";
        networkConfig = {
          Bridge =
            if p.role == "trunk" then "br-cobalt-lan" else accessBridge p.vlan;
        };
      };

  # Every cobalt-owned netdev gets a networkd rule: the management port
  # (`lan5`, internal switch port 0 -- mainline already labels it, so it is not
  # in the generated overlay) plus the MxL 2.5G jacks that carry the trunk and
  # access roles.  `portMap.ports` is internalPorts ++ mxlPorts.
  managedPorts =
    portMap.ports
    ++ [{ label = portMap.mgmtLabel; role = "management"; }];

  lanNetworks = lib.listToAttrs (map mkPortNetwork managedPorts);
in
{
  # networkd owns the cobalt ports and the bridges; the scripted/dhcpcd client
  # would fight it for the same interfaces.
  systemd.network.enable = true;
  networking.useNetworkd = true;
  networking.useDHCP = lib.mkForce false;

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
  }
  # One VLAN child per access VLAN, derived from the LAN trunk.  Names must be
  # <= 15 bytes (IFNAMSIZ); "br-cobalt-lan.30" would be 16 and is rejected.
  // lib.listToAttrs (map
    (vlan: {
      name = "20-cobalt-lan.${toString vlan}";
      value = {
        netdevConfig = {
          Name = "cobalt-lan.${toString vlan}";
          Kind = "vlan";
        };
        vlanConfig.Id = vlan;
      };
    })
    accessVlans)
  # Untagged segment the access ports of each VLAN join.
  // lib.listToAttrs (map
    (vlan: {
      name = accessBridge vlan;
      value.netdevConfig = {
        Name = accessBridge vlan;
        Kind = "bridge";
      };
    })
    accessVlans);

  systemd.network.networks = lanNetworks // {
    "10-br-cobalt-lan" = {
      matchConfig.Name = "br-cobalt-lan";
      linkConfig.RequiredForOnline = "no";
      # Feed every access VLAN the host terminates off the trunk.
      networkConfig.VLAN = [ "cobalt-lan.${toString clientsVlan}" ];
    };

    "10-br-cobalt-wan" = {
      matchConfig.Name = "br-cobalt-wan";
      linkConfig.RequiredForOnline = "no";
      networkConfig = { };
    };

    # The SFP+ WAN MAC (eth1) is the bridge member the cobalt VM's WAN NIC
    # attaches to.  The VM terminates VLAN 300 on it itself (eth1.300), so the
    # host only hands over the raw L2 port -- same shape as the vendor OpenWrt
    # br-wan = eth1.  eth1 must not be addresed by the host.
    "10-eth1" = {
      matchConfig.Name = "eth1";
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "br-cobalt-wan";
    };

    # The access bridge carrying the host's own DHCP management address (the
    # host's management/underlay, used by nebula and for SSH, rides the trunk as
    # tagged VLAN 30 rather than a dedicated mgmt jack, so it survives a
    # missing/moved mgmt cable).  The cobalt VM still owns routing/NAT here.
    #
    # Only VLAN 30 is host-addressed.  VLAN 50's bridge deliberately gets NO
    # address: it is a pass-through for the bench, and the host must not take a
    # second management address on it.
    "20-vlan${toString clientsVlan}" = {
      matchConfig.Name = accessBridge clientsVlan;
      linkConfig.RequiredForOnline = "yes";
      networkConfig = {
        DHCP = "ipv4";
        LinkLocalAddressing = "no";
      };
    };
  }
    # Every remaining access VLAN still needs a `.network` file, even though it
    # is deliberately unaddressed.  Without one, systemd-networkd never matches
    # the bridge and leaves it `unmanaged`/DOWN: the .netdev creates vlan50, the
    # jack (mxl_lan2) enslaves to it correctly, but the bridge carries no
    # traffic, so the IoT bench jack is dead while looking wired up.
    #
    # These are pure L2 pass-throughs, so they take no address and no DHCP; the
    # cobalt VM is the only thing that may address them.
    // lib.listToAttrs
    (map
      (vlan: {
        name = "20-vlan${toString vlan}";
        value = {
          matchConfig.Name = accessBridge vlan;
          # A bench jack must never hold up boot: its cable may be unplugged.
          linkConfig.RequiredForOnline = "no";
          networkConfig = {
            DHCP = "no";
            LinkLocalAddressing = "no";
          };
        };
      })
      (lib.filter (vlan: vlan != clientsVlan) accessVlans))
    // lib.listToAttrs
    (map
      (vlan: {
        name = "20-cobalt-lan.${toString vlan}";
        value = {
          matchConfig.Name = "cobalt-lan.${toString vlan}";
          linkConfig.RequiredForOnline = "no";
          networkConfig.Bridge = accessBridge vlan;
        };
      })
      accessVlans);

  # QEMU attaches the VM's NICs with the setuid qemu-bridge-helper, which
  # refuses any bridge not listed in /etc/qemu/bridge.conf.  The libvirtd
  # module normally provides both the file and the setuid wrapper; s-nodus runs
  # QEMU directly through nixos-shell, so declare them here (same owner/group
  # and source as the libvirtd module).
  environment.etc."qemu/bridge.conf".text = ''
    allow br-cobalt-lan
    allow br-cobalt-wan
  '';

  security.wrappers.qemu-bridge-helper = {
    setuid = true;
    owner = "root";
    group = "root";
    source = "${pkgs.qemu}/libexec/qemu-bridge-helper";
  };

  # The bridge helper needs tun/tap.
  boot.kernelModules = [ "tun" ];

  # The bridges are host-private L2 plumbing; no host firewall/nat on them.
  networking.firewall.checkReversePath = false;
}
