{
  pkgs,
  lib,
  self,
}:

name:
{
  description ? "NixOS VM (nixos-shell)",
  keep ? 1,
  # this is the working dir for the qcow2 files.
  workingDir ? "/persist/nix-shell-vms",
  # this is the dir where /persist is mounted in the vm.
  persistDir ? "/persist/vm-persists",
  extraTmpfiles ? [ ],
  repository ? "path:${self.outPath}",
}:

let
  serviceName = "${name}-vm";
  qmpSocket = "/run/${serviceName}.qmp";
  flakeRef = "${repository}";
in
{
  systemd.services.${serviceName} = {
    inherit description;

    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];

    # ⛔ REMOVED wantedBy to prevent boot-time execution
    # wantedBy = [ "multi-user.target" ];

    path = [
      pkgs.nix
      pkgs.socat
      pkgs.coreutils
      pkgs.screen
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 10;
      User = "root";

      ExecStart = pkgs.writeShellScript "start-${serviceName}" ''
        set -euo pipefail
        cd ${workingDir}

        ROOT_DIR=/var/lib/nixos-shell
        KEEP=${toString keep}
        VM_NAME="${name}"

        mkdir -p "$ROOT_DIR"

        OUT="$ROOT_DIR/$VM_NAME-$(date --rfc-3339=seconds | tr ' ' '_')"

        ${pkgs.nix}/bin/nix build \
          ${flakeRef}#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell \
          --out-link "$OUT"

        ls -dt "$ROOT_DIR"/"$VM_NAME"-* 2>/dev/null \
          | tail -n +$((KEEP+1)) \
          | xargs -r rm

        export QEMU_OPTS="-qmp unix:${qmpSocket},server=on,wait=off"

        exec ${pkgs.screen}/bin/screen -DmS "$VM_NAME" \
          ${pkgs.nix}/bin/nix run \
          ${flakeRef}#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell
      '';

      ExecStop = pkgs.writeShellScript "stop-${serviceName}" ''
        set -u

        if [ -S "${qmpSocket}" ]; then
          printf '%s\n' \
            '{"execute":"qmp_capabilities"}' \
            '{"execute":"system_powerdown"}' \
          | ${pkgs.socat}/bin/socat - UNIX-CONNECT:${qmpSocket} || true
        fi

        while [ -S "${qmpSocket}" ]; do
          sleep 1
        done
      '';

      TimeoutStopSec = "2min";
      KillMode = "process";

      ProtectHome = false;
      PrivateTmp = true;
      StateDirectory = name;
      WorkingDirectory = workingDir;
    };
  };
  systemd.timers.${serviceName} = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1sec";
      Unit = serviceName;
    };
  };


  systemd.tmpfiles.rules =
    [
      "d ${workingDir} 0755 root root -"
      "d ${persistDir} 0755 root root -"
      "d /persist/vm-persists/${name} 0755 root root -"
    ]
    ++ extraTmpfiles;
}

