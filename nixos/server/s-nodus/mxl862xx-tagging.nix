# MxL86252 (mxl862xx DSA) tagging mode for the BPI-R4 Pro 4E.
#
# Why (measured on this board, 2026-11-09):
#   The mxl862xx driver defaults to the switch's native 8-byte "special tag"
#   (SpTag). The MT7988 Ethernet controller cannot parse it, so every frame
#   the switch delivers is dropped by mtk_tag_rcv with
#
#     net eth2: Invalid special tag marker, packet dropped, tag: 3d a3 03 00 ...
#
#   Once that starts (~9 min after boot on this board) the shared PPE/DMA state
#   degrades and the next TX burst takes the whole host down: last journal line
#   was a nebula handshake, then nothing, console included.
#
# OpenWrt solved the same defect by adding an 802.1Q-VLAN-based DSA tag driver
# for these switches ("net: dsa: add 802.1Q VLAN-based tag driver for
# MxL862xx", Daniel Golle), because the SpTag "is not compatible with all SoC
# Ethernet controllers". That tag driver is already in our kernel (6.18.60:
# net/dsa/tag_mxl862xx_8021q.ko, protocol name "mxl862xx-8021q"); it is simply
# not selected.
#
# Selecting it at runtime is refused with EBUSY by DSA
# (dsa_tree_change_tag_proto: "we don't allow changing the tag protocol under
# traffic" -- every user port must be down). networkd brings the ports up, so
# the switch has to be performed before networkd runs, hence this unit.
{ pkgs, ... }:

{
  systemd.services."mxl862xx-8021q-tagging" = {
    description = "Select 802.1Q DSA tagging for the MxL86252 switch";
    # Strictly before anything configures the switch ports.
    before = [
      "systemd-networkd.service"
      "network-pre.target"
    ];
    # `network-pre.target` is a passive target: being wanted by it does not
    # pull the unit in. multi-user is the active ordering point that brings it
    # in, and `before` keeps it ahead of the first networkd run.
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = ''
      conduit=/sys/class/net/eth2/dsa/tagging

      # Nothing to do on hardware without the MaxLinear switch.
      [ -w "$conduit" ] || exit 0

      current="$(cat "$conduit")"
      if [ "$current" = "mxl862xx-8021q" ]; then
        exit 0
      fi

      # DSA refuses the change while any user port is up.
      for port in /sys/class/net/mxl_lan*; do
        [ -e "$port" ] || continue
        ip link set "$(basename "$port")" down || true
      done

      if ! echo "mxl862xx-8021q" > "$conduit"; then
        echo "mxl862xx-8021q-tagging: could not switch tagging (still $(cat "$conduit"))" >&2
        exit 1
      fi
      echo "mxl862xx-8021q-tagging: DSA tagging is now $(cat "$conduit")"
    '';
  };
}
