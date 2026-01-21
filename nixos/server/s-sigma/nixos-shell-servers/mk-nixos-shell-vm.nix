{
  pkgs,
  lib,
  self,
}:

name:
{
  description ? "NixOS VM (nixos-shell)",
  workingDir ? "/persist/nix-shell-vms",
  persistDir ? "/persist/vm-persists",
  extraTmpfiles ? [ ],
  repository ? "path:${self.outPath}",
  restartTime ? 5,
  ephemeralRoot ? false,

  # Image manager behavior
  buildDelaySec ? 600,
  buildIntervalSec ? 600,
  pinned ? false,
  nixBuildFlags ? [ ],
}:

let
  vmServiceName = "${name}-vm";
  imageServiceName = "${name}-image";
  flakeRef = "${repository}";

  # QMP for graceful shutdown
  qmpSocket = "/run/${vmServiceName}.qmp";

  # tmux attach socket (stable, predictable path)
  tmuxDir = "/run/nixos-shell";
  tmuxSocket = "${tmuxDir}/${name}.tmux";
  tmuxSession = "vm";

  qcow2Path = "${workingDir}/${name}.qcow2";

  # Persistent, host-side image state (GC roots)
  imgBase = "/persist/nixos-shell-images/${name}";
  currentLink = "${imgBase}/current";
  candidateLink = "${imgBase}/candidate";
  pinLock = "${imgBase}/pin.lock";

  nixBuildFlagsStr = lib.concatStringsSep " " (map lib.escapeShellArg nixBuildFlags);

  buildAttr = "${flakeRef}#nixosConfigurations.${name}.config.system.build.nixos-shell";
in
{
  # Keep visibility of the built VM image (optional, but consistent)
  system.build.vmImages.${name} = self.nixosConfigurations.${name}.config.system.build.nixos-shell;

  #####################################################################
  # 1) IMAGE MANAGER — TIMER DRIVEN ONLY
  #####################################################################
  systemd.services.${imageServiceName} = {
    description = "NixOS VM image manager (nixos-shell) for ${name}";

    after = [
      "network-online.target"
      "nix-daemon.service"
    ];
    wants = [ "network-online.target" ];

    path = [
      pkgs.nix
      pkgs.coreutils
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    script = ''
      set -euo pipefail
      mkdir -p "${imgBase}"

      ${lib.optionalString pinned ''
        : > "${pinLock}"
      ''}

      if [ -f "${pinLock}" ]; then
        echo "[image] pinned -> skipping build"
        exit 0
      fi

      echo "[image] building candidate for ${name} ..."
      nix build ${nixBuildFlagsStr} "${buildAttr}" --out-link "${candidateLink}"

      NEW_PATH="$(readlink -f "${candidateLink}")"
      echo "[image] candidate -> $NEW_PATH"

      if [ ! -e "${currentLink}" ]; then
        ln -sfn "$NEW_PATH" "${currentLink}"
        echo "[image] initialized current"
        exit 0
      fi

      OLD_PATH="$(readlink -f "${currentLink}" || true)"

      if [ "$NEW_PATH" = "$OLD_PATH" ]; then
        echo "[image] current already up-to-date"
        exit 0
      fi

      ln -sfn "$NEW_PATH" "${currentLink}"
      echo "[image] promoted current (will restart VM)"

      /run/current-system/sw/bin/systemctl try-restart "${vmServiceName}.service" || true
    '';
  };

  systemd.timers.${imageServiceName} = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "${toString buildDelaySec}s";
      OnUnitActiveSec = "${toString buildIntervalSec}s";
      Unit = "${imageServiceName}.service";
    };
  };

  #####################################################################
  # 2) VM RUNNER — NO ENV VARS, MANUALLY-RUNNABLE SCRIPT
  #####################################################################
  systemd.services.${vmServiceName} = {
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
      pkgs.tmux
      pkgs.bash
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = restartTime;
      User = "root";

      ExecStart = pkgs.writeShellScript "start-${vmServiceName}" ''
        set -euo pipefail

        WORKDIR="${workingDir}"
        IMG_BASE="${imgBase}"
        CURRENT_LINK="${currentLink}"
        CANDIDATE_LINK="${candidateLink}"
        TMUX_SOCKET="${tmuxSocket}"
        TMUX_SESSION="${tmuxSession}"
        QMP_SOCKET="${qmpSocket}"

        mkdir -p "$WORKDIR"
        mkdir -p "$IMG_BASE"
        mkdir -p "${tmuxDir}"

        # Seed image if needed
        if [ ! -e "$CURRENT_LINK" ]; then
          echo "[vm] no current image -> building seed (blocking)"
          nix build ${nixBuildFlagsStr} "${buildAttr}" --out-link "$CANDIDATE_LINK"
          SEED="$(readlink -f "$CANDIDATE_LINK")"
          ln -sfn "$SEED" "$CURRENT_LINK"
          echo "[vm] seeded current -> $SEED"
        fi

        IMG="$(readlink -f "$CURRENT_LINK")"
        echo "[vm] using image -> $IMG"

        ${lib.optionalString ephemeralRoot ''
          echo "[vm] ephemeralRoot=true -> deleting ${qcow2Path}"
          rm -f "${qcow2Path}" || true
        ''}

        # Start detached tmux session running the exact command you validated
        if ! tmux -S "$TMUX_SOCKET" has-session -t "$TMUX_SESSION" 2>/dev/null; then
          tmux -S "$TMUX_SOCKET" new-session -d -s "$TMUX_SESSION" \
            bash -lc "export QEMU_OPTS='-qmp unix:$QMP_SOCKET,server=on,wait=off'; \"$IMG/bin/run-${name}-vm\""
        fi

        # Keep systemd alive while the VM is alive
        while true; do
          if ! tmux -S "$TMUX_SOCKET" has-session -t "$TMUX_SESSION" 2>/dev/null; then
            echo "[vm] tmux session vanished"
            break
          fi
          sleep 2
        done

        echo "[vm] tmux session exited; restarting"
        exit 1
      '';

      ExecStop = pkgs.writeShellScript "stop-${vmServiceName}" ''
        set -u

        QMP_SOCKET="${qmpSocket}"
        TMUX_SOCKET="${tmuxSocket}"
        TMUX_SESSION="${tmuxSession}"

        if [ -S "$QMP_SOCKET" ]; then
          printf '%s\n' \
            '{"execute":"qmp_capabilities"}' \
            '{"execute":"system_powerdown"}' \
          | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"$QMP_SOCKET" || true
        fi

        end=$((SECONDS + 110))
        while [ -S "$QMP_SOCKET" ] && [ $SECONDS -lt $end ]; do
          sleep 1
        done

        if [ -S "$TMUX_SOCKET" ]; then
          tmux -S "$TMUX_SOCKET" kill-session -t "$TMUX_SESSION" 2>/dev/null || true
        fi
      '';

      TimeoutStopSec = "2min";
      KillMode = "process";

      ProtectHome = false;
      PrivateTmp = true;
      StateDirectory = name;
      WorkingDirectory = workingDir;
    };
  };

  # Start VM shortly after boot
  systemd.timers.${vmServiceName} = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1sec";
      Unit = "${vmServiceName}.service";
    };
  };

  #####################################################################
  # Directories and persistence
  #####################################################################
  systemd.tmpfiles.rules = [
    "d ${workingDir} 0755 root root -"
    "d ${persistDir} 0755 root root -"
    "d /persist/vm-persists/${name} 0755 root root -"
    "d ${imgBase} 0755 root root -"
    "d ${tmuxDir} 0755 root root -"
    (lib.optionalString pinned "f ${pinLock} 0644 root root - -")
  ]
  ++ extraTmpfiles;
}
