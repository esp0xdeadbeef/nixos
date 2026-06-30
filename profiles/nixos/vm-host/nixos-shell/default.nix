{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.vmHost.nixosShell;
  eno1RouterVms = cfg.eno1RouterVms;
  routerVmUnits = eno1RouterVms.units;
  escapedRouterVmUnits = lib.concatMapStringsSep " " lib.escapeShellArg routerVmUnits;
in {
  options.local.vmHost.nixosShell.autoStart = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Whether nixos-shell VMs should start from their generated systemd timers.";
  };

  options.local.vmHost.nixosShell.eno1RouterVms = {
    enable = lib.mkEnableOption "starting or stopping nixos-shell router VMs based on host eno1 carrier";

    interface = lib.mkOption {
      type = lib.types.str;
      default = "eno1";
      description = "Host interface whose carrier controls the router VM units.";
    };

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "s-router-legacy-edge-vm.service"
        "s-router-legacy-core-vm.service"
      ];
      description = "systemd units controlled by the interface carrier watcher.";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log the systemctl action that would run without starting or stopping VM units.";
    };
  };

  config = {
    environment.systemPackages = [
      pkgs.tmux
      pkgs.qemu
      pkgs.socat
    ];

    systemd.services.nixos-shell-eno1-router-vms = lib.mkIf eno1RouterVms.enable {
      description = "Start or stop legacy router nixos-shell VMs from ${eno1RouterVms.interface} carrier";
      wantedBy = ["multi-user.target"];
      after = ["sys-subsystem-net-devices-${eno1RouterVms.interface}.device"];
      wants = ["sys-subsystem-net-devices-${eno1RouterVms.interface}.device"];

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

        iface=${lib.escapeShellArg eno1RouterVms.interface}
        state_file="/run/nixos-shell-$iface-router-vms.state"

        carrier_state() {
          if [ -r "/sys/class/net/$iface/carrier" ] && [ "$(cat "/sys/class/net/$iface/carrier" 2>/dev/null || printf 0)" = 1 ]; then
            printf up
          else
            printf down
          fi
        }

        run_action() {
          action="$1"
          ${lib.optionalString eno1RouterVms.dryRun ''
          echo "dry-run: would run: systemctl $action --no-block ${escapedRouterVmUnits}"
        ''}
          ${lib.optionalString (!eno1RouterVms.dryRun) ''
          systemctl "$action" --no-block ${escapedRouterVmUnits}
        ''}
        }

        apply_state() {
          state="$1"
          log_change="$2"
          if [ "$state" = up ]; then
            if [ "$log_change" = true ]; then
              echo "$iface carrier is up; ${
          if eno1RouterVms.dryRun
          then "router VMs would be started"
          else "starting router VMs"
        }"
            fi
            run_action start
          else
            if [ "$log_change" = true ]; then
              echo "$iface carrier is down; ${
          if eno1RouterVms.dryRun
          then "router VMs would be stopped"
          else "stopping router VMs"
        }"
            fi
            run_action stop
          fi
        }

        last_state=

        while true; do
          current_state="$(carrier_state)"

          if [ "$current_state" != "$last_state" ]; then
            printf '%s\n' "$current_state" > "$state_file"
            apply_state "$current_state" true
            last_state="$current_state"
          fi

          sleep 5
        done
      '';
    };
  };
}
