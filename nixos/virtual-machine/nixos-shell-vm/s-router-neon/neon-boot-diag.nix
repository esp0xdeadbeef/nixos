{ config, lib, pkgs, ... }:
let
  diagScript = pkgs.writeShellScript "neon-boot-diag" ''
    set -u
    out=/var/log/neon-boot-diag.log
    ts="$(date +%s)"
    {
      echo "=== neon boot diag ts=$ts ==="
      echo "--- host interfaces ---"
      ip -br addr || true
      ip -br link || true
      echo "--- containers ---"
      machinectl list || echo "machinectl list failed"
      for c in core upstream-selector policy downstream-selector access-vlan2 access-vlan3 access-vlan7 access-vlan8; do
        echo "--- container $c ---"
        if machinectl shell "$c" /bin/sh -c 'ip -br addr; echo; ip -br link; echo; ip rule; echo; ip route' 2>&1; then
          :
        else
          echo "FAILED to enter $c"
        fi
      done
      echo "--- beacon reachability from access-vlan3 (lan3 -> 192.168.3.10) ---"
      if machinectl shell access-vlan3 /bin/sh -c 'ping -c1 -W2 192.168.3.10' 2>&1; then
        echo "BEACON_REACHABLE"
      else
        echo "BEACON_UNREACHABLE"
      fi
      echo "--- policy nftables (forward chain, first 60 lines) ---"
      machinectl shell policy /bin/sh -c 'nft list ruleset' 2>&1 | sed -n '1,60p'
      echo "=== end diag ==="
    } > "$out" 2>&1
    # Mirror to the console so a live ssh capture during the window also sees it.
    cat "$out" > /dev/console 2>/dev/null || true
  '';
in
{
  systemd.services.neon-boot-diag = {
    description = "Capture neon router post-boot network state";
    wantedBy = [ "multi-user.target" ];
    after = [ "machines.target" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = diagScript;
    };
  };
}
