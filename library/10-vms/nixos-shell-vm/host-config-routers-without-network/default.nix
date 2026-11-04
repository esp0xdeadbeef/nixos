{ config
, lib
, pkgs
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.nixos-shell-host.common

    ./vm-settings.nix
    ./restart-container.nix
    ./ssh.nix
    ./impermanence.nix
    ./persist-state-disk.nix
  ];


  # vhost-net NICs render as `-netdev tap,ifname=tap-<nicId>,vhost=on,queues=N`
  # because qemu rejects `vhost`/`queues` inside `-nic` and `-netdev bridge`
  # ("Invalid parameter ..."). A bare tap is NOT bridged by qemu, so the host
  # must enslave it; otherwise the guest loses its fabric attachment.
  #
  # The tap only exists once qemu opened the netdev, so this polls for it
  # instead of relying on a static VM-unit hook (the nixos-shell runner owns
  # that unit and exposes no extension point).
  options.local.vhostTapAttachments = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        tap = lib.mkOption { type = lib.types.str; };
        bridge = lib.mkOption { type = lib.types.str; };
      };
    });
    default = [ ];
    description = "vhost tap devices to enslave to their rendered bridges";
  };

  config = lib.mkMerge [
    {
      # The VM manager's health check, `vm-exec`, and every diagnostic in this
      # repo talk to the guest through the QEMU guest agent over
      # org.qemu.guest_agent.0. Without an explicit enable the unit ships in
      # the closure but is never started, so a healthy guest is reported
      # unhealthy and the manager restores the previous image. Declared here so
      # every router guest (cobalt-new, nixos lab, prod) answers by construction.
      services.qemuGuest.enable = true;
    }

    (lib.mkIf (config.local.vhostTapAttachments != [ ]) {
    systemd.services.vhost-tap-attach = {
      description = "Enslave vhost-net tap devices to their rendered bridges";
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 pkgs.coreutils pkgs.gnugrep ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -u

        attach() {
          tap="$1"
          bridge="$2"
          i=0
          while [ "$i" -lt 120 ]; do
            if ip link show dev "$tap" >/dev/null 2>&1; then
              ip link set dev "$tap" master "$bridge"
              ip link set dev "$tap" up
              echo "attached $tap -> $bridge"
              return 0
            fi
            i=$((i + 1))
            sleep 1
          done
          echo "ERROR: $tap never appeared" >&2
          return 1
        }

        ${lib.concatMapStringsSep "\n" (
          a: "attach ${lib.escapeShellArg a.tap} ${lib.escapeShellArg a.bridge}"
        ) config.local.vhostTapAttachments}
      '';
    };
    })
  ];
}
