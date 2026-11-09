{ config, lib, pkgs, ... }:

# Networking for s-nodus (BPI-R4 Pro 4E).
#
# Management/underlay is DHCP on lan5 (see ./cobalt-bridges.nix, which owns the
# networkd rules).  The board is NOT itself a router: the cobalt site router
# runs as the s-router-cobalt-new VM, and the only host-side network role is
# the L2 plumbing that feeds that VM's NICs (./cobalt-bridges.nix).
let
  cfg = config.local.bpiR4Pro;
in
{
  config = lib.mkIf cfg.enable {
    # The host does not route or NAT; the VM owns all routing/NAT behaviour.
    networking.nat.enable = false;
    networking.firewall.enable = false;

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 0;
      "net.ipv6.conf.all.forwarding" = 0;
    };

    # The MT7988 TXD ring corruption (0x77777777 poison, TX timeout) is the
    # known TSO-path bug this board hits; the driver-side recovery is in the
    # kernel patches (981/982).  Host-side TSO/GSO is kept off on every MAC of
    # the mtk_eth_soc instance (eth0..eth2 + the DSA conduit end0) regardless:
    # these are bridge members, so offloads buy nothing, and disabling them
    # removes the trigger rather than relying on the recovery path.  Kept
    # idempotent and re-applied whenever networkd restarts.
    #
    # This unit must ASSERT the result, not just attempt it.  It previously
    # ended every ethtool call in `|| true` with no readback, and the unit was
    # absent from the running system for a month (generation 72 predates it)
    # while ethtool reported tx-tcp-segmentation: on -- i.e. the board ran
    # without its documented mitigation and nothing noticed.  Interfaces are
    # skipped when the device is not present yet (the unit also re-runs on
    # link events), but a present interface that still has TSO/GSO on fails
    # the unit loudly.
    systemd.services.mtk-eth-tso-off = {
      description = "Disable TSO/GSO on all MediaTek ethernet MACs";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-networkd.service" ];
      # Re-apply when networkd is restarted: a netdev stop/start (e.g. patch
      # 981's per-netdev recovery) re-enables offloads, and bridge members only
      # matter once they are up.  partOf (not bindsTo) so this unit is
      # restarted with networkd rather than torn down permanently.
      partOf = [ "systemd-networkd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [
        config.systemd.package
        pkgs.ethtool
        pkgs.gnugrep
        # The readback assertion uses awk; without gawk here the unit dies with
        # "awk: command not found" (status 127) and TSO silently stays on.
        pkgs.gawk
      ];
      script = ''
        set -u
        rc=0
        checked=0
        for iface in /sys/class/net/eth[0-9] /sys/class/net/end0; do
          [ -d "$iface" ] || continue
          name=''${iface##*/}
          checked=$((checked + 1))

          ethtool -K "$name" tso off gso off 2>/dev/null \
            || echo "mtk-eth-tso-off: $name: ethtool -K tso/gso off failed" >&2

          # EEE on MT7988 (BPI-R4) is a known wedge trigger (OpenWrt forum,
          # 6.12+ mediatek filogic); these are 10G trunk/uplink ports where
          # EEE saves nothing.
          ethtool --set-eee "$name" eee off 2>/dev/null \
            || echo "mtk-eth-tso-off: $name: ethtool --set-eee eee off failed" >&2

          # Readback: these are the features this unit exists to turn off.
          for feat in tcp-segmentation-offload generic-segmentation-offload; do
            state=$(ethtool -k "$name" 2>/dev/null \
              | grep -E "^''${feat}:" | awk '{print $2}')
            if [ "''${state:-unknown}" != "off" ]; then
              echo "mtk-eth-tso-off: $name: ''${feat} is ''${state:-unknown}, expected off" >&2
              rc=1
            fi
          done
        done

        if [ "$checked" -eq 0 ]; then
          echo "mtk-eth-tso-off: no MediaTek interfaces present yet; the timer will retry" >&2
        fi
        exit "$rc"
      '';
    };

    # The unit above runs early, and on this board the MTK netdevs (eth1/eth2)
    # are NOT up yet at that point: the unit logs "no MediaTek interfaces
    # present yet" and, until now, nothing ever re-ran it -- the comment claimed
    # "re-run on link events" but no such trigger existed. Result: TSO/GSO
    # stayed ON for the whole boot and the MACs kept emitting frames with
    # garbage L2 headers (ethertype 0x4d54, HTTP text as MAC addresses).
    #
    # Drive it from a timer instead of hoping for link events: cheap (a handful
    # of ethtool calls), idempotent, and it self-heals after a networkd restart
    # or a driver re-probe.
    systemd.timers.mtk-eth-tso-off = {
      description = "Re-apply TSO/GSO off on the MediaTek MACs";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "5min";
        Unit = "mtk-eth-tso-off.service";
      };
    };
  };
}
