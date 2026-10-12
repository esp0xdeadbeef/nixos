{ config, lib, pkgs, ... }:

# Board kernel for the BPI-R4 Pro (MT7988A).
#
# Why not just linuxPackages_latest: mainline's mtk_eth_soc has NO USXGMII/SerDes
# support, so the on-board 10G switch (MxL86252) CPU conduit and the SFP+ cages
# cannot come up -- the WAN is simply unsupported on mainline.  This is the same
# gap the README lists as the "10G switch / SFP+ ... OpenWrt-delta kernel" TODO.
#
# We therefore build nixpkgs' DEFAULT linux_6_18 with the curated OpenWrt MT7988
# networking delta (mtk_eth_soc USXGMII + DSA mxl862xx + PCS mtk-usxgmii/lynxi)
# applied.  The delta was rebased from OpenWrt (via the ly4096x/BananaPi-R4-Pro-8X-OS
# tree, GPL-2.0) onto nixpkgs' 6.18.55; see patches/openwrt-mt7988-net-6.18.55.patch.
#
# Config is set via structuredExtraConfig on top of nixpkgs' base (a superset),
# so we only turn the board drivers on and the big unused subsystems off.
let
  baseKernel = pkgs.linux_6_18;
in
{
  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor (
    baseKernel.override (prev: {
      kernelPatches = (prev.kernelPatches or [ ]) ++ [
        {
          name = "openwrt-mt7988-net";
          patch = ./patches/openwrt-mt7988-net-6.18.55.patch;
        }
        # mt7530-mdio.c must match the delta's reworked mtk_pcs_lynxi_create()
        # signature (dev, fwnode, regmap, ana_rgc3), otherwise it is a real
        # incompatible-pointer/int-conversion bug on the lan5 SerDes PCS path.
        {
          name = "mt7530-pcs-lynxi-sig";
          patch = ./patches/980-mt7530-match-mtk-pcs-lynxi-create-signature.patch;
        }
        # AS21010 10G PHY (the 10G RJ45 WAN/combo) fixes from the same OpenWrt
        # tree: handle pipelined C45 reads, force a pipelined no-op aneg, and
        # fix a warm-reboot pipeline lag.
        {
          name = "as21xxx-pipelined-aneg";
          patch = ./patches/976-as21xxx-bind-force-pipelined-noop-aneg.patch;
        }
        {
          name = "as21xxx-warmreboot";
          patch = ./patches/979-as21xxx-warmreboot-fix.patch;
        }
        # mtk USXGMII PCS: do not reset the line side after link-up.
        {
          name = "pcs-mtk-usxgmii-no-reset";
          patch = ./patches/977-pcs-mtk-usxgmii-no-reset-after-linkup.patch;
        }
      ];
      structuredExtraConfig = (prev.structuredExtraConfig or { }) // (with lib.kernel; {
        # --- board networking drivers (the delta provides the code) ---
        NET_MEDIATEK_SOC = module;
        NET_MEDIATEK_SOC_WED = yes;
        NET_DSA = module;
        NET_DSA_MXL862 = module;
        NET_DSA_TAG_MXL_862XX = module;
        NET_DSA_TAG_MXL_862XX_8021Q = module;
        PCS_MTK_LYNXI = yes;
        PCS_MTK_USXGMII = yes;
        FWNODE_PCS = yes;
        PHY_COMMON_PROPS = yes;
        # 2.5G/10G PHYs used by the board
        MEDIATEK_2P5GE_PHY = module;
        MAXLINEAR_GPHY = module;
        # SFP cage support (sfp1 = LAN, sfp2 = WAN)
        SFP = module;
        # nixpkgs' common-config enables DAMON + all its sub-options.  DAMON's
        # reclaim/stat engines run kdamond continuously (~22% of a core here),
        # scanning and reclaiming memory and competing with kswapd.  Keep DAMON
        # itself on (its sub-options are only valid when it is, and disabling it
        # makes them "unused" and fails the config check), but turn off the
        # engines that actually burn CPU.
        DAMON_RECLAIM = lib.mkForce no;
        DAMON_LRU_SORT = lib.mkForce no;
        DAMON_STAT = lib.mkForce no;
      });
    })
  ));
}
