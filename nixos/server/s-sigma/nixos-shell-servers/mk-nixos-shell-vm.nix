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
  restartTime ? 1,
  # NEW: if true, the VM disk is wiped before every start
  ephemeralRoot ? false,
}:

let
  serviceName = "${name}-vm";
  qmpSocket = "/run/${serviceName}.qmp";
  flakeRef = "${repository}";

  # Where nixos-shell keeps the VM disk by default
  #qcow2Path = "/var/lib/nixos-shell/${name}.qcow2";
  qcow2Path = "${workingDir}/${name}.qcow2";

in
{
  system.build.vmImages.${name} = self.nixosConfigurations.${name}.config.system.build.nixos-shell;

  systemd.services.${serviceName} = {
    inherit description;

    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];

    path = [
      pkgs.nix
      pkgs.socat
      pkgs.coreutils
      pkgs.screen
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = restartTime;
      User = "root";

      # Make the chosen mode visible in journalctl
      Environment = [
        "NIXOS_SHELL_EPHEMERAL_ROOT=${if ephemeralRoot then "1" else "0"}"
      ];

      ExecStart = pkgs.writeShellScript "start-${serviceName}" ''
        set -eu

        cd ${workingDir}

        ROOT_DIR=/var/lib/nixos-shell
        KEEP=${toString keep}
        VM_NAME="${name}"

        mkdir -p "$ROOT_DIR"

        ${lib.optionalString ephemeralRoot ''
          echo "[nixos-shell] ephemeralRoot=true → deleting ${qcow2Path}"
          rm -f "${qcow2Path}" || true
        ''}

        OUT="$ROOT_DIR/$VM_NAME-$(date --rfc-3339=seconds | tr ' ' '_')"

        # Build the VM derivation and keep a rolling window to defeat nix-gc
        ${pkgs.nix}/bin/nix build \
          ${flakeRef}#nixosConfigurations.$VM_NAME.config.system.build.nixos-shell \
          --out-link "$OUT" &

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

  systemd.tmpfiles.rules = [
    "d ${workingDir} 0755 root root -"
    "d ${persistDir} 0755 root root -"
    "d /persist/vm-persists/${name} 0755 root root -"
  ]
  ++ extraTmpfiles;
}
