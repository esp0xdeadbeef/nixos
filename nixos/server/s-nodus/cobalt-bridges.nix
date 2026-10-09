{ lib, pkgs, ... }:

# Cobalt host-side platform binding for the s-router-cobalt-new VM
# (Banana Pi BPI-R4 Pro 4E).
#
# Role (mirrors nixos/laptop/l-envil/hardware/cobalt-bridges.nix):
#   lan2  -> 802.1Q trunk into br-cobalt-lan   (carries the cobalt LAN trunk)
#   lan3  -> access port, untagged (VLAN 30)    (clients)
#   lan5  -> management (DHCP, host uplink/nebula) -- NOT part of the bridges
#   sfp1/sfp2 -> SFP+ cages; sfp2 is the WAN source for VM activation
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

  # VLAN used for the untagged access ports (matches the cobalt clients plane).
  clientVlan = 30;

  # networkd `.network` stanza for one mapped port, keyed by its DT label.
  #   trunk      -> 802.1Q trunk into br-cobalt-lan
  #   access     -> untagged clients VLAN into the vlan30 access bridge
  #   unused     -> realized netdev, no bridge (jack present, no cobalt role)
  #   management -> handled separately below (DHCP on its own netdev)
  mkPortNetwork = p:
    if p.role == "management" then
      lib.nameValuePair "10-${p.label}"
        {
          matchConfig.Name = p.label;
          linkConfig.RequiredForOnline = "yes";
          networkConfig = {
            DHCP = "ipv4";
            LinkLocalAddressing = "no";
          };
        }
    else
      lib.nameValuePair "10-${p.label}" {
        matchConfig.Name = p.label;
        linkConfig.RequiredForOnline = "no";
        networkConfig = lib.mkIf (p.role == "trunk" || p.role == "access") {
          Bridge =
            if p.role == "trunk" then "br-cobalt-lan" else "vlan${toString clientVlan}";
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
  # would fight it for the same interfaces.  Management (lan5) moves to a
  # networkd DHCP rule below.
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

    # VLAN ${toString clientVlan} derived from the LAN trunk.  Its name must be
    # <= 15 bytes (IFNAMSIZ); "br-cobalt-lan.30" would be 16 and is rejected.
    "20-cobalt-lan.${toString clientVlan}" = {
      netdevConfig = {
        Name = "cobalt-lan.${toString clientVlan}";
        Kind = "vlan";
      };
      vlanConfig.Id = clientVlan;
    };

    # Untagged VLAN ${toString clientVlan} segment the access ports join.
    "20-vlan${toString clientVlan}" = {
      netdevConfig = {
        Name = "vlan${toString clientVlan}";
        Kind = "bridge";
      };
    };
  };

  systemd.network.networks = lanNetworks // {
    # br-cobalt-lan terminates the client VLAN off the trunk into the
    # untagged access bridge.
    "10-br-cobalt-lan" = {
      matchConfig.Name = "br-cobalt-lan";
      linkConfig.RequiredForOnline = "no";
      networkConfig.VLAN = [ "cobalt-lan.${toString clientVlan}" ];
    };

    "10-br-cobalt-wan" = {
      matchConfig.Name = "br-cobalt-wan";
      linkConfig.RequiredForOnline = "no";
      networkConfig = { };
    };

    # VLAN child off the trunk -> untagged access bridge.
    "20-cobalt-lan.${toString clientVlan}" = {
      matchConfig.Name = "cobalt-lan.${toString clientVlan}";
      linkConfig.RequiredForOnline = "no";
      networkConfig.Bridge = "vlan${toString clientVlan}";
    };

    # The access bridge itself is pure L2 (the cobalt VM owns addressing).
    "20-vlan${toString clientVlan}" = {
      matchConfig.Name = "vlan${toString clientVlan}";
      linkConfig.RequiredForOnline = "no";
      networkConfig = { };
    };
  };

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
