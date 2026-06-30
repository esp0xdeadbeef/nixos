{ lib, pkgs, ... }:

let
  interface = "eno1";
  routerVmUnits = [
    "s-router-legacy-edge-vm.service"
    "s-router-legacy-core-vm.service"
  ];
  escapedRouterVmUnits = lib.concatMapStringsSep " " lib.escapeShellArg routerVmUnits;
in
{
  systemd.services.nixos-shell-eno1-router-vms = {
    description = "Start or stop legacy router nixos-shell VMs from eno1 carrier";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-${interface}.device" ];
    wants = [ "sys-subsystem-net-devices-${interface}.device" ];

    path = [
      pkgs.coreutils
      pkgs.systemd
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
    };

    script = ''
      set -euo pipefail

      iface=${lib.escapeShellArg interface}
      state_file="/run/nixos-shell-$iface-router-vms.state"

      carrier_state() {
        if [ -r "/sys/class/net/$iface/carrier" ] && [ "$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || printf 0)" = 1 ]; then
          printf up
        else
          printf down
        fi
      }

      apply_state() {
        state="$1"
        log_change="$2"
        if [ "$state" = up ]; then
          if [ "$log_change" = true ]; then
            echo "$iface carrier is up; starting router VMs"
          fi
          systemctl start --no-block ${escapedRouterVmUnits}
        else
          if [ "$log_change" = true ]; then
            echo "$iface carrier is down; stopping router VMs"
          fi
          systemctl stop --no-block ${escapedRouterVmUnits}
        fi
      }

      last_state=
      ticks=0

      while true; do
        current_state="$(carrier_state)"
        ticks=$((ticks + 1))

        if [ "$current_state" != "$last_state" ] || [ "$ticks" -ge 6 ]; then
          printf '%s\n' "$current_state" > "$state_file"
          if [ "$current_state" != "$last_state" ]; then
            apply_state "$current_state" true
          else
            apply_state "$current_state" false
          fi
          last_state="$current_state"
          ticks=0
        fi

        sleep 5
      done
    '';
  };
}
