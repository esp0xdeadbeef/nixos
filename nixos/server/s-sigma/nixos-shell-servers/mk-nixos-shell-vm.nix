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
  repository ? "path:${self.lib.vmSourceFor name}",
  restartTime ? 5,
  ephemeralRoot ? true,

  buildDelaySec ? 600,
  buildIntervalSec ? 600,
  pinned ? false,
  nixBuildFlags ? [ ],

  stateDiskSize ? "100G",
}:

let
  vmServiceName = "${name}-vm";
  imageServiceName = "${name}-image";

  flakeRef = "${repository}";
  qmpSocket = "/run/${vmServiceName}.qmp";

  tmuxDir = "/run/nixos-shell";
  tmuxSocket = "${tmuxDir}/${name}.tmux";
  tmuxSession = "vm";

  qcow2Path = "${workingDir}/${name}.qcow2";

  imgBase = "/persist/nixos-shell-images/${name}";
  currentLink = "${imgBase}/current";
  candidateLink = "${imgBase}/candidate";
  pinLock = "${imgBase}/pin.lock";

  nixBuildFlagsStr = lib.concatStringsSep " " (map lib.escapeShellArg nixBuildFlags);

  perVmPersistDir = "${persistDir}/${name}";
  stateDiskPath = "${perVmPersistDir}/state.qcow2";

  # SAFE: each token escaped, then joined
  qemuExtraOpts = lib.concatStringsSep " " (
    map lib.escapeShellArg [
      "-qmp"
      "unix:${qmpSocket},server=on,wait=off"
      "-drive"
      "file=${stateDiskPath},if=virtio,format=qcow2,cache=none,aio=native"
    ]
  );

  innerStart = pkgs.writeShellScript "inner-${vmServiceName}" ''
    set -euo pipefail

    mkdir -p "${tmuxDir}" "${workingDir}" "${imgBase}" "${perVmPersistDir}"

    if [ -n "''${NIXOS_VM_FLAKE:-}" ]; then
      FLAKE="path:''${NIXOS_VM_FLAKE}"
    else
      FLAKE="${flakeRef}"
    fi
    BUILD_ATTR="''${FLAKE}#nixosConfigurations.${name}.config.system.build.nixos-shell"

    if [ ! -e "${stateDiskPath}" ]; then
      echo "Creating persistent state disk: ${stateDiskPath} (${stateDiskSize})"
      ${pkgs.qemu}/bin/qemu-img create -f qcow2 "${stateDiskPath}" "${stateDiskSize}" >/dev/null
    fi

    if [ ! -e "${currentLink}" ]; then
      nix build ${nixBuildFlagsStr} "''${BUILD_ATTR}" --out-link "${candidateLink}"
      ln -sfn "$(readlink -f "${candidateLink}")" "${currentLink}"
    fi

    ${lib.optionalString ephemeralRoot ''rm -f "${qcow2Path}" || true''}

    CMD="export QEMU_OPTS='${qemuExtraOpts}'; exec \"$(readlink -f "${currentLink}")/bin/run-${name}-vm\""

    echo "$CMD" > "${tmuxDir}/${name}.cmd"

    if ! tmux -S "${tmuxSocket}" has-session -t "${tmuxSession}" 2>/dev/null; then
      tmux -S "${tmuxSocket}" new-session -d -s "${tmuxSession}" bash -lc "$CMD"
    fi

    while tmux -S "${tmuxSocket}" has-session -t "${tmuxSession}" 2>/dev/null; do
      sleep 2
    done

    exit 1
  '';

  stableLauncher = "/run/nixos-shell/${name}.sh";
in
{
  system.build.vmImages.${name} = self.nixosConfigurations.${name}.config.system.build.nixos-shell;

  systemd.services.${imageServiceName} = {
    description = "VM image manager (nixos-shell) for ${name}";
    after = [ "nix-daemon.service" ];
    path = [
      pkgs.nix
      pkgs.coreutils
      pkgs.systemd
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

      if [ -f "${pinLock}" ]; then exit 0; fi

      if [ -n "''${NIXOS_VM_FLAKE:-}" ]; then
        FLAKE="path:''${NIXOS_VM_FLAKE}"
      else
        FLAKE="${flakeRef}"
      fi
      BUILD_ATTR="''${FLAKE}#nixosConfigurations.${name}.config.system.build.nixos-shell"

      nix build ${nixBuildFlagsStr} "''${BUILD_ATTR}" --out-link "${candidateLink}"

      NEW_PATH="$(readlink -f "${candidateLink}")"
      OLD_PATH="$(readlink -f "${currentLink}" 2>/dev/null || true)"
      if [ "$NEW_PATH" = "$OLD_PATH" ]; then exit 0; fi

      ln -sfn "$NEW_PATH" "${currentLink}"
      systemctl restart "${vmServiceName}.service" || true
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

  systemd.services.${vmServiceName} = {
    inherit description;
    stopIfChanged = false;
    reloadIfChanged = false;

    unitConfig = {
      DefaultDependencies = false;
      IgnoreOnIsolate = true;
      Before = [ "shutdown.target" ];
      Conflicts = [ "shutdown.target" ];
    };

    after = lib.mkForce [ ];
    wants = lib.mkForce [ ];
    requires = lib.mkForce [ ];
    bindsTo = lib.mkForce [ ];
    partOf = lib.mkForce [ ];
    wantedBy = lib.mkForce [ ];

    path = [
      pkgs.nix
      pkgs.socat
      pkgs.coreutils
      pkgs.tmux
      pkgs.bash
      pkgs.qemu
    ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = restartTime;
      User = "root";
      KillMode = "process";
      TimeoutStopSec = "2min";
      WorkingDirectory = workingDir;
      ExecStart = stableLauncher;

      ExecStop = pkgs.writeShellScript "stop-${vmServiceName}" ''
        set -euo pipefail
        if [ -S "${qmpSocket}" ]; then
          printf '%s\n' \
            '{"execute":"qmp_capabilities"}' \
            '{"execute":"system_powerdown"}' \
          | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"${qmpSocket}" || true
        fi
        sleep 5
        tmux -S "${tmuxSocket}" kill-session -t "${tmuxSession}" 2>/dev/null || true
      '';
    };
  };

  systemd.timers.${vmServiceName} = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1";
      Unit = "${vmServiceName}.service";
    };
  };

  systemd.tmpfiles.rules = [
    "L+ ${stableLauncher} - - - - ${innerStart}"
    "d ${workingDir} 0755 root root -"
    "d ${persistDir} 0755 root root -"
    "d ${perVmPersistDir} 0755 root root -"
    "d ${imgBase} 0755 root root -"
    "d ${tmuxDir} 0755 root root -"
    (lib.optionalString pinned "f ${pinLock} 0644 root root - -")
  ]
  ++ extraTmpfiles;
}
