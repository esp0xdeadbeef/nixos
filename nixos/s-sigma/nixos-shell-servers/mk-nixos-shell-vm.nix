{ pkgs, lib }:

name:
{
  description ? "NixOS VM (nixos-shell)",
  keep ? 1,
  workingDir ? "/persist/nix-shell-vms",
  extraTmpfiles ? [ ],
  repostiory ? "path:/home/deadbeef/github/nixos",
}:

let
  serviceName = "${name}-vm";
  qmpSocket = "/run/${serviceName}.qmp";
in
{
  systemd.services.${serviceName} = {
    inherit description;

    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

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

      # -------------------------
      # START
      # -------------------------
      ExecStart = pkgs.writeShellScript "start-${serviceName}" ''
        set -euo pipefail
        cd ${workingDir}

        ROOT_DIR=/var/lib/nixos-shell
        KEEP=${toString keep}
        VM_NAME="${name}"

        mkdir -p "$ROOT_DIR"

        OUT="$ROOT_DIR/$VM_NAME-$(date --rfc-3339=seconds | sed 's/ /_/g')"

        nix build \
          ${repostiory}#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell \
          --out-link "$OUT"

        ls -dt "$ROOT_DIR"/"$VM_NAME"-* 2>/dev/null \
          | tail -n +$((KEEP+1)) \
          | xargs -r rm

        export QEMU_OPTS="-qmp unix:${qmpSocket},server=on,wait=off"

        exec screen -DmS "$VM_NAME" nix run \
          ${repostiory}#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell
      '';

      # -------------------------
      # STOP (graceful ACPI)
      # -------------------------
      ExecStop = pkgs.writeShellScript "stop-${serviceName}" ''
        set -u

        if [ -S "${qmpSocket}" ]; then
          printf '%s\n' \
            '{"execute":"qmp_capabilities"}' \
            '{"execute":"system_powerdown"}' \
          | ${pkgs.socat}/bin/socat - UNIX-CONNECT:${qmpSocket} || true
        fi

        # Wait until QEMU exits (socket disappears)
        while [ -S "${qmpSocket}" ]; do
          sleep 1
        done
      '';

      # Give the guest time to shut down cleanly
      TimeoutStopSec = "2min";

      # CRITICAL: don't SIGTERM the whole cgroup immediately
      KillMode = "process";

      # Optional: keep default KillSignal (SIGTERM) is fine.
      # KillSignal = "SIGTERM";

      ProtectHome = false;
      PrivateTmp = true;
      StateDirectory = name;
      WorkingDirectory = workingDir;
    };
  };

  systemd.tmpfiles.rules = [
    "d ${workingDir} 0755 root root -"
    "d /persist/vm-persists/${name} 0755 root root -"
    # DO NOT pre-create the QMP socket as a regular file.
    # QEMU creates the unix socket itself.
    # "f ${qmpSocket} 0660 root root -"
  ]
  ++ extraTmpfiles;
}
