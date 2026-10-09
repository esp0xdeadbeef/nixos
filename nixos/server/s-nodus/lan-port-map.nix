{ lib }:

# Physical Ethernet port map for s-nodus (Banana Pi BPI-R4 Pro 4E).
#
# VERIFIED against the vendor (BPI-SINOVOIP) datasheet "On board Ethernet" for
# the 4E and the vendor GettingStarted port descriptions:
#
#   1x 2.5G RJ45 WAN (combo with 10G SFP+ WAN)      -> gmac1
#   2x 1G RJ45 LAN                                   -> internal switch port 0, 2
#   4x 2.5G RJ45 LAN                                 -> MxL86252 ports 0..3
#   1x 1G LAN (FPC Connector, needs an adapter)      -> internal switch port 3
#   1x 10G SFP+ LAN                                  -> MxL86252 SerDes port 6
#   1x 10G SFP+ WAN (combo)                          -> gmac1 USXGMII1
#
# Vendor GettingStarted: "The 1G RJ45 of BPI-R4Pro is connected to Port0 of the
# internal switch of MT7988A" and "The 1G ETH FPC connector of BPI-R4Pro is
# connected to Port3 of the internal switch of MT7988A".  The second 1G RJ45
# LAN jack (datasheet) is internal switch port 2.  Internal switch port 1 has
# NO connector at all (the vendor 4E DTS deletes port@1 and keeps only its
# PHY/LED), so we never expose it as a netdev.
#
# The DT stanzas below are SOURCED FROM the vendor's own board DTS (open source,
# SPDX GPL-2.0 OR MIT):
#   BPI-SINOVOIP/BPI-R4PRO-4E-OPENWRT-V24.10.0-Master-Devel
#   commit d876c3d6, target/linux/mediatek/files-6.6/arch/arm64/boot/dts/
#   mediatek/mt7988a-bananapi-bpi-r4-pro-4e.dts
# and copied here so the port map cannot drift from the hardware.  Only the
# minimal adaptations required to build against the MAINLINE kernel tree we run
# are applied; each is marked `[mainline]` and is a mechanism change, not a
# change of meaning:
#
#   * compatible "mxl,86252" -> "maxlinear,mxl86252" (mainline driver's
#     of_device_id, drivers/net/dsa/mxl862xx/mxl862xx.c).
#   * the switch's `dsa-tag-protocol = "mxl862_8021q"` is dropped: mainline
#     uses its own tag protocol name ("mxl862xx") and provisions it by default
#     for this driver, so forcing the vendor string would fail to resolve.
#   * `&switch { ports { /delete-node/ port@1; } }` is dropped: fdtoverlay does
#     not implement /delete-node/, and the mainline board dtsi already leaves
#     gsw_port1 `status = "disabled"`, so port@1 stays non-existent either way.
#   * the `gbeN_led0_pins` group nodes are added here because the mainline board
#     dtsi only defines `gbe0_led0_pins`; the SoC pinctrl driver already knows
#     the `gbeN_led0` pin groups (pins 64..67).
#
# Role meanings (realization mechanics, no network meaning; FS-176/FS-187):
#   trunk      -> 802.1Q trunk into br-cobalt-lan
#   access     -> untagged clients VLAN into the untagged access bridge
#   management -> host uplink (DHCP), left on its own netdev, not bridged
#   unused     -> realized as a plain DT-enabled netdev, not bridged
let
  # Management jack: MT7988 internal switch port 0, labelled `lan5` by the
  # mainline board dtsi (the vendor/OpenWrt name for the same jack is `lan0`).
  mgmtLabel = "lan5";

  # The 1G jacks/connectors driven by the MT7988 internal switch that carry a
  # Internal switch jacks on THIS board.
  #
  # The board's own ID EEPROM reads `R4PRO8X` and its jack population is the
  # 8X one: ONE 1G RJ45 jack (internal switch port 0 -> `lan5`), four 2.5G RJ45
  # jacks (MxL86252), two SFP+ cages and one combo.  Internal switch ports 1..3
  # have NO connectors here, which is exactly what mainline's board dtsi means by
  # "R4Pro has only port 0 connected".  We therefore enable NO extra internal
  # ports: `lan5` (port 0) is management, and the cobalt trunk/access roles go
  # on the real 2.5G jacks (see mxlPorts below).
  internalPorts = [ ];

  # Internal switch port 1 has a PHY/LED but no jack; keep the LED alive and
  # leave the port disabled (mainline's board dtsi already does).
  ledOnlyPhyPorts = [ 1 ];

  # MxL86252 copper jacks.
  #
  # [mainline] mainline's mxl862xx DSA driver uses its OWN port numbering, which
  # differs from the vendor/OpenWrt binding: port 0 is the *microcontroller*
  # port (normally disabled), ports 1..8 are the PHYs, and the SerDes are
  # ports 9..16 (MXL862XX_FIRST_SERDES_PORT = 9, 4 slots; port 9 = SerDes slot 0,
  # port 13 = slot 1).  The vendor DTS numbers the copper jacks port@0..3 (so
  # mainline treats the vendor's port@0 as the microcontroller port and its
  # SPTAG setup fails with -E22 -> mxl_lan0 never appears), and puts the CPU on
  # reg=8 / the SFP on reg=12 (mainline expects those at port 9 / port 13).
  #
  #   DSA port = mainline port index (node name + reg)
  #   phyAddr  = MDIO address of the port's PHY (vendor: 0..3)
  #   label    = netdev name
  #   role     = how cobalt-bridges.nix wires it
  #
  # The four 2.5G jacks are the real cobalt-facing ports on this board: the
  # trunk (tagged VLAN 30) on mxl_lan0 and the untagged access port on
  # mxl_lan1; mxl_lan2/mxl_lan3 are spare.
  mxlPorts = [
    { port = 1; phyAddr = 0; label = "mxl_lan0"; role = "trunk"; }
    { port = 2; phyAddr = 1; label = "mxl_lan1"; role = "access"; }
    { port = 3; phyAddr = 2; label = "mxl_lan2"; role = "unused"; }
    { port = 4; phyAddr = 3; label = "mxl_lan3"; role = "unused"; }
  ];

  # MxL SerDes ports (mainline numbering): port 9 = CPU (USXGMII0 -> gmac2),
  # port 13 = USXGMII1 -> the sfp1 cage.
  mxlCpuPort = 9;
  mxlSfpPort = 13;

  # SoC pinctrl group names for the switch-PHY LEDs (vendor mt7988a.dtsi).
  ledPinGroup = n: "gbe${toString n}_led0_pins";
  ledPinNode = n: "gbe${toString n}-led0-pins";

  # ---- vendored + adapted vendor node text ------------------------------------
  #
  # MxL86252 (vendor switch@16 stanza), with the two [mainline] edits applied.
  mxlStanza = ''
    &mdio_bus {
      switch@16 {
        compatible = "maxlinear,mxl86252"; /* [mainline] was "mxl,86252" */
        reg = <16>;
        dsa,member = <0 0>;
        status = "okay";

        ports {
          #address-cells = <1>;
          #size-cells = <0>;

    ${lib.concatMapStrings (p: ''
          port@${toString p.port} {
            reg = <${toString p.port}>;
            label = "${p.label}";
            phy-handle = <&switchphy${toString p.phyAddr}>;
            phy-mode = "internal";
            status = "okay";
          };
    '') mxlPorts}
          port@${toString mxlCpuPort} {
            reg = <${toString mxlCpuPort}>;
            label = "cpu";
            phy-mode = "usxgmii";
            ethernet = <&gmac2>;
            /* [mainline] dsa-tag-protocol dropped (driver default "mxl862xx") */

            fixed-link {
              speed = <10000>;
              full-duplex;
            };
          };

          port@${toString mxlSfpPort} {
            reg = <${toString mxlSfpPort}>;
            label = "mxl_lan5";
            /* [mainline] the vendor DTS uses phy-mode = "10gbase-r" +
               managed = "in-band-status", but mainline's mxl862xx PCS
               reports LINK_INBAND_DISABLE for PHY_INTERFACE_MODE_10GBASER,
               which makes DSA's in-band validation fail (-EINVAL).  USXGMII
               reports LINK_INBAND_ENABLE, so use usxgmii for the SFP SerDes
               (also what the CPU port side of the XPCS uses).  DSA requires
               one of phy-handle / fixed-link / managed on a user port; the
               SFP has no PHY, so managed = "in-band-status" is the
               appropriate one. */
            phy-mode = "usxgmii";
            managed = "in-band-status";
            sfp = <&sfp1>;
            status = "okay";
          };
        };

        mdio {
          #address-cells = <1>;
          #size-cells = <0>;

    ${lib.concatMapStrings (p: ''
          switchphy${toString p.phyAddr}: switchphy@${toString p.phyAddr} {
            reg = <${toString p.phyAddr}>;
          };
    '') mxlPorts}
        };
      };
    };
  '';

  # Base-DTS fragment: emitted after `#include` of the mainline board dtsi,
  # inside the same compilation unit, so labels resolve against the SoC tree.
  baseFragment = ''
    /* LED pin groups for switch PHYs 1..3 (board dtsi only defines PHY0). */
    &pio {
    ${lib.concatMapStrings (n: ''
      ${ledPinGroup n}: ${ledPinNode n} {
        mux {
          function = "led";
          groups = "gbe${toString n}_led0";
        };
      };
    '') ([ 1 2 3 ])}
    };

    /* Internal switch: enable the jacks that exist (2 and 3). */
    ${lib.concatMapStrings (p: ''
      &gsw_phy${toString p.switchPort} {
        status = "okay";
        pinctrl-names = "gbe-led";
        pinctrl-0 = <&${ledPinGroup p.switchPort}>;
      };
      &gsw_port${toString p.switchPort} {
        status = "okay";
        label = "${p.label}";
      };
    '') internalPorts}

    /* Internal switch port 1 has a PHY/LED but no jack on the 4E: keep the LED
       alive and leave the port disabled (mainline default), so no fake netdev
       appears.  The vendor's /delete-node/ port@1 is not needed on mainline. */
    &gsw_phy1 {
      status = "okay";
      pinctrl-names = "gbe-led";
      pinctrl-0 = <&gbe1_led0_pins>;
    };

    ${mxlStanza}

    /* gmac2 is the MxL86252 CPU conduit: mainline's mtk_soc_eth requires a
       phy-mode on every enabled MAC, and the vendor board DTS gives gmac2
       `phy-mode = "10gbase-r"` + a 10G fixed-link.  Without this the whole
       mtk_soc_eth probe fails with -EINVAL ("incorrect phy-mode") and the
       board boots with NO ethernet at all. */
    &gmac2 {
      phy-mode = "10gbase-r";
      phy-connection-type = "10gbase-r";
      status = "okay";
      fixed-link {
        speed = <10000>;
        full-duplex;
      };
    };

    /* gmac1 is the 2.5G RJ45/10G SFP+ WAN combo.  The host does not need it
       (the cobalt VM owns WAN), and mainline cannot enable it without a
       phy-mode/PHY the way the vendor kernel can -- so leave it disabled. */
  '';
in
{
  # Consumed by ./dtb.nix (baseFragment) and ./cobalt-bridges.nix (roles).
  inherit internalPorts mxlPorts mgmtLabel baseFragment;

  # Every cobalt-owned netdev with its role:
  #   lan5 -> management, lan2 -> trunk, lan3 -> access,
  #   mxl_lan0..3 -> unused (jack exists, no cobalt role yet).
  ports = internalPorts ++ mxlPorts;
}
