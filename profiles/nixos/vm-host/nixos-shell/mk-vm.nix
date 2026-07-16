{ config ? null
, pkgs
, lib
, self
,
}:

name:
{ description ? "NixOS VM (nixos-shell)"
, workingDir ? "/persist/nix-shell-vms"
, persistDir ? "/persist/vm-persists"
, extraTmpfiles ? [ ]
, repository ? "path:${self.lib.vmSourceForHost name}"
, updateFlakeLocks ? false
, updateOnGuestShutdown ? true
, updateImageBeforeStart ? false
, restartVmAfterImageUpdate ? false
, imageUpdateTimer ? false
, imageServiceBefore ? [ ]
, safeRestart ? false
, restartTime ? 5
, ephemeralRoot ? true
, buildDelaySec ? 600
, buildIntervalSec ? 600
, pinned ? false
, nixBuildFlags ? [ ]
, stateDiskSize ? "100G"
, registerImage ? true
, autoStart ? (
    if config == null then
      true
    else
      config.local.vmHost.nixosShell.autoStart or true
  )
,
}:

assert lib.assertMsg (!updateImageBeforeStart || registerImage)
  "${name}: updateImageBeforeStart requires registerImage = true";
assert lib.assertMsg (lib.hasPrefix "path:/nix/store/" repository)
  "${name}: repository must be the store-pinned source captured by the host switch";
assert lib.assertMsg (!restartVmAfterImageUpdate || registerImage)
  "${name}: restartVmAfterImageUpdate requires registerImage = true";
assert lib.assertMsg (!(updateImageBeforeStart && restartVmAfterImageUpdate))
  "${name}: updateImageBeforeStart and restartVmAfterImageUpdate are mutually exclusive";
assert lib.assertMsg (!restartVmAfterImageUpdate || !updateOnGuestShutdown)
  "${name}: restartVmAfterImageUpdate requires updateOnGuestShutdown = false";
assert lib.assertMsg (!imageUpdateTimer || registerImage)
  "${name}: imageUpdateTimer requires registerImage = true";
assert lib.assertMsg (!safeRestart || registerImage)
  "${name}: safeRestart requires registerImage = true";

let
  vmServiceName = "${name}-vm";
  imageServiceName = "${name}-image";
  rolloutServiceName = "${name}-rollout";
  automaticUpdateMode =
    if updateFlakeLocks || imageUpdateTimer || restartVmAfterImageUpdate then
      "--force"
    else
      "--if-stale";
  automaticGeneration = toString self.outPath;
  qmpSocket = "/run/${vmServiceName}.qmp";

  tmuxDir = "/run/nixos-shell";
  tmuxSocket = "${tmuxDir}/${name}.tmux";
  tmuxSession = "vm";
  stopMarker = "${tmuxDir}/${name}.stopping";

  qcow2Path = "${workingDir}/${name}.qcow2";

  imgBase = "/persist/nixos-shell-images/${name}";
  # sadly it din't cache it last time i've tried this, so i was offline (core router):
  runImgBase = "/persist/nixos-shell-images/${name}";

  currentLink = "${imgBase}/current";
  candidateLink = "${runImgBase}/candidate";

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

  updateImageProgram = pkgs.writeShellScriptBin "update-image-${name}" ''
    set -euo pipefail

    mode=force
    non_blocking=false

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --force)
          mode=force
          ;;
        --if-stale)
          mode=if-stale
          ;;
        --non-blocking)
          non_blocking=true
          ;;
        *)
          echo "usage: update-image-${name} [--force|--if-stale] [--non-blocking]" >&2
          exit 64
          ;;
      esac
      shift
    done

    image_root="''${NIXOS_SHELL_IMAGE_ROOT:-${imgBase}}"
    current_link="$image_root/current"
    candidate_link="$image_root/candidate"
    pin_lock="$image_root/pin.lock"
    attempt_file="$image_root/last-automatic-attempt"
    host_lock="$image_root/update.lock"
    global_lock="''${NIXOS_SHELL_GLOBAL_UPDATE_LOCK:-/run/lock/nixos-shell-image-update.lock}"
    generation="''${NIXOS_SHELL_UPDATE_GENERATION:-${automaticGeneration}}"
    source_flake="''${NIXOS_SHELL_SOURCE_FLAKE:-${repository}}"
    nix_bin="''${NIXOS_SHELL_NIX_BIN:-${pkgs.nix}/bin/nix}"
    nix_store_bin="''${NIXOS_SHELL_NIX_STORE_BIN:-${pkgs.nix}/bin/nix-store}"
    flock_bin="''${NIXOS_SHELL_FLOCK_BIN:-${pkgs.util-linux}/bin/flock}"

    mkdir -p "$image_root" "$(dirname "$global_lock")"

    if [ -e "$pin_lock" ]; then
      echo "${name}: image is pinned by $pin_lock"
      exit 0
    fi

    exec 8>"$host_lock"
    if [ "$non_blocking" = true ]; then
      if ! "$flock_bin" -n 8; then
        echo "${name}: an image update for this VM is already active; keeping the cached image"
        exit 0
      fi
    else
      "$flock_bin" 8
    fi

    if [ "$mode" = if-stale ]; then
      previous_generation="$(cat "$attempt_file" 2>/dev/null || true)"
      if [ "$previous_generation" = "$generation" ]; then
        echo "${name}: automatic image update already attempted for $generation"
        exit 0
      fi

      attempt_tmp="$attempt_file.tmp.$$"
      printf '%s\n' "$generation" >"$attempt_tmp"
      mv -f "$attempt_tmp" "$attempt_file"
    fi

    exec 9>"$global_lock"
    if [ "$non_blocking" = true ]; then
      if ! "$flock_bin" -n 9; then
        echo "${name}: another image build is active; keeping the cached image"
        exit 0
      fi
    else
      "$flock_bin" 9
    fi

    build_candidate() {
      local flake_ref="$1"

      "$nix_bin" build \
        ${nixBuildFlagsStr} \
        "$flake_ref#nixosConfigurations.${name}.config.system.build.nixos-shell" \
        --out-link "$candidate_link"
    }

    ${lib.optionalString updateFlakeLocks ''
      build_with_updated_locks() {
      local source_ref="$1"
      local source_path=
      local worktree=
      local status=0

      case "$source_ref" in
        path:*)
          source_path="''${source_ref#path:}"
          ;;
        *)
          echo "${name}: lock updates require a path: source, got $source_ref" >&2
          return 64
          ;;
      esac

      worktree="$(mktemp -d "$image_root/.flake-update.XXXXXX")"
      cp -a --reflink=auto "$source_path/." "$worktree/"
      chmod -R u+w "$worktree"

      "$nix_bin" flake update --refresh --flake "path:$worktree" || status=$?
      if [ "$status" -eq 0 ]; then
        build_candidate "path:$worktree" || status=$?
      fi

      rm -rf "$worktree"
      return "$status"
      }
    ''}

    current_image="$(readlink -f "$current_link" 2>/dev/null || true)"
    current_runner="$current_image/bin/run-${name}-vm"

    build_status=0
    ${
      if updateFlakeLocks then
        ''
      build_with_updated_locks "$source_flake" || build_status=$?
    ''
      else
        ''
      build_candidate "$source_flake" || build_status=$?
    ''
    }

    if [ "$build_status" -ne 0 ]; then
      if [ -n "$current_image" ] && [ -x "$current_runner" ]; then
        echo "${name}: image update failed; keeping $current_image" >&2
        exit 1
      fi

      ${
      if updateFlakeLocks then
        ''
      echo "${name}: lock-updated build failed; trying the switch-pinned flake.lock" >&2
      if ! build_candidate "$source_flake"; then
        echo "${name}: fallback build failed and no cached image exists" >&2
        exit 1
      fi
    ''
      else
        ''
        echo "${name}: store-pinned image update failed and no cached fallback exists" >&2
        exit 1
      ''
    }
    fi

    new_image="$(readlink -f "$candidate_link")"
    new_runner="$new_image/bin/run-${name}-vm"
    if [ -z "$new_image" ] || [ ! -x "$new_runner" ]; then
      echo "${name}: candidate does not contain $new_runner; keeping the cached image" >&2
      exit 1
    fi

    old_image="$(readlink -f "$current_link" 2>/dev/null || true)"
    if [ "$new_image" = "$old_image" ]; then
      echo "${name}: cached image is already current: $new_image"
      exit 0
    fi

    "$nix_store_bin" \
      --add-root "$current_link" \
      --indirect \
      --realise "$new_image" >/dev/null

    echo "${name}: cached image updated: ''${old_image:-<none>} -> $new_image"
  '';

  updateImageCli = pkgs.writeShellScriptBin "update-image" ''
    set -euo pipefail

    mode=--force
    non_blocking=()
    host=

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --force|--if-stale)
          mode="$1"
          ;;
        --non-blocking)
          non_blocking=(--non-blocking)
          ;;
        -* )
          echo "usage: update-image [--force|--if-stale] [--non-blocking] <hostname>" >&2
          exit 64
          ;;
        *)
          if [ -n "$host" ]; then
            echo "usage: update-image [--force|--if-stale] [--non-blocking] <hostname>" >&2
            exit 64
          fi
          host="$1"
          ;;
      esac
      shift
    done

    if [ -z "$host" ] || [[ "$host" == *[!a-zA-Z0-9-]* ]]; then
      echo "usage: update-image [--force|--if-stale] [--non-blocking] <hostname>" >&2
      exit 64
    fi

    worker="/run/nixos-shell/$host-update-image"
    if [ ! -x "$worker" ]; then
      echo "$host is not a registered nixos-shell image" >&2
      exit 66
    fi

    exec "$worker" "$mode" "''${non_blocking[@]}"
  '';

  runVmCli = pkgs.writeShellScriptBin "run-vm" ''
      set -euo pipefail

      if [ "$#" -ne 1 ] || [[ "$1" == *[!a-zA-Z0-9-]* ]]; then
        echo "usage: run-vm <hostname>" >&2
        exit 64
      fi

      host="$1"
      image_root="/persist/nixos-shell-images/$host"
      current_link="$image_root/current"
      current_image="$(readlink -f "$current_link" 2>/dev/null || true)"
      current_runner="$current_image/bin/run-$host-vm"
      tmux_socket="/run/nixos-shell/$host.tmux"
      service="$host-vm.service"
      runner_lock="/run/lock/nixos-shell-run-$host.lock"

      mkdir -p /run/lock
      exec 9>"$runner_lock"
      if ! ${pkgs.util-linux}/bin/flock -n 9; then
        echo "another run-vm supervisor is already attached to $host" >&2
        exit 75
      fi

      if ! ${updateImageCli}/bin/update-image --force "$host"; then
        echo "$host: update failed; trying the cached image" >&2
      fi

      current_image="$(readlink -f "$current_link" 2>/dev/null || true)"
      current_runner="$current_image/bin/run-$host-vm"
      if [ -z "$current_image" ] || [ ! -x "$current_runner" ]; then
        echo "$host: no usable cached image; leaving the VM stopped" >&2
        exit 69
      fi

    ${pkgs.systemd}/bin/systemctl start "$service"

    while true; do
      session_ready=false
      for _ in $(${pkgs.coreutils}/bin/seq 1 90); do
        if ${pkgs.tmux}/bin/tmux -S "$tmux_socket" has-session -t vm 2>/dev/null; then
          session_ready=true
          break
        fi

        unit_state="$(${pkgs.systemd}/bin/systemctl is-active "$service" 2>/dev/null || true)"
        case "$unit_state" in
          active|activating)
            ;;
          *)
            ${pkgs.systemd}/bin/systemctl start "$service" || true
            ;;
        esac
        ${pkgs.coreutils}/bin/sleep 1
      done

        if [ "$session_ready" != true ]; then
          echo "$host: tmux session did not appear" >&2
          exit 1
        fi

        trap true INT
        TMUX= ${pkgs.tmux}/bin/tmux -S "$tmux_socket" attach -t vm || true
      trap - INT

      if ${pkgs.tmux}/bin/tmux -S "$tmux_socket" has-session -t vm 2>/dev/null; then
        exit 0
      fi
    done
  '';

  innerStart = pkgs.writeShellScript "inner-${vmServiceName}" ''
    set -euo pipefail

    runtime_image_root="''${NIXOS_SHELL_IMAGE_ROOT:-${imgBase}}"
    runtime_current_link="$runtime_image_root/current"
    cached_image="$(readlink -f "$runtime_current_link" 2>/dev/null || true)"
    cached_runner="$cached_image/bin/run-${name}-vm"
    if [ -z "$cached_image" ] || [ ! -x "$cached_runner" ]; then
      echo "${name}: no usable cached image at $runtime_current_link" >&2
      exit 69
    fi

    mkdir -p "${tmuxDir}" "${workingDir}" "${imgBase}" "${perVmPersistDir}" "${runImgBase}"
    rm -f "${stopMarker}"

    if [ ! -e "${stateDiskPath}" ]; then
      echo "Creating persistent state disk: ${stateDiskPath} (${stateDiskSize})"
      ${pkgs.qemu}/bin/qemu-img create -f qcow2 "${stateDiskPath}" "${stateDiskSize}" >/dev/null
    fi

    ${lib.optionalString ephemeralRoot ''rm -f "${qcow2Path}" || true''}

    CMD="export QEMU_OPTS='${qemuExtraOpts}'; exec \"$cached_runner\""

    echo "$CMD" > "${tmuxDir}/${name}.cmd"

    if ! tmux -S "${tmuxSocket}" has-session -t "${tmuxSession}" 2>/dev/null; then
      tmux -S "${tmuxSocket}" new-session -d -s "${tmuxSession}" bash -lc "$CMD"
    fi

    while tmux -S "${tmuxSocket}" has-session -t "${tmuxSession}" 2>/dev/null; do
      sleep 2
    done

    if [ -e "${stopMarker}" ]; then
      rm -f "${stopMarker}"
      exit 0
    fi

    exit 1
  '';

  updateAfterGuestShutdown = pkgs.writeShellScript "update-image-after-${name}-shutdown" ''
    set -u

    if [ "''${SERVICE_RESULT:-success}" = success ]; then
      exit 0
    fi

    system_state="$(${pkgs.systemd}/bin/systemctl is-system-running 2>/dev/null || true)"
    if [ "$system_state" = stopping ]; then
      echo "${name}: host is stopping; skipping the guest-shutdown image update"
      exit 0
    fi

    if ! ${updateImageProgram}/bin/update-image-${name} ${automaticUpdateMode}; then
      echo "${name}: guest-shutdown image update failed; the cached image remains active" >&2
    fi

    exit 0
  '';

  activateImageProgram = pkgs.writeShellApplication {
    name = "activate-image-${name}";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.systemd
      pkgs.tmux
      pkgs.util-linux
    ];
    text = ''
      export NIXOS_SHELL_HOST=${lib.escapeShellArg name}
      ${builtins.readFile ./activate-vm-image-safely.sh}
    '';
  };

  safeRestartProgram = pkgs.writeShellApplication {
    name = "restart-${name}";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nix
      pkgs.procps
      pkgs.systemd
      pkgs.tmux
      pkgs.util-linux
    ];
    text = ''
      export NIXOS_SHELL_HOST=${lib.escapeShellArg name}
      export NIXOS_SHELL_IMAGE_SERVICE_ROLLOUT=${lib.boolToString restartVmAfterImageUpdate}
      export NIXOS_SHELL_ROLLOUT_SERVICE=${lib.escapeShellArg "${rolloutServiceName}.service"}
      ${builtins.readFile ./restart-vm-safely.sh}
    '';
  };

  stableLauncher = "/run/nixos-shell/${name}.sh";
in
{
  system.build."vmImage-${name}" = lib.mkIf registerImage self.nixosConfigurations.${name}.config.system.build.nixos-shell;
  system.build."vmImageUpdater-${name}" = lib.mkIf registerImage updateImageProgram;
  system.build."vmLauncher-${name}" = innerStart;
  system.build."updateImageCli-${name}" = updateImageCli;
  system.build."runVmCli-${name}" = runVmCli;
  system.build."activateVmImage-${name}" = lib.mkIf registerImage activateImageProgram;
  system.build."safeRestart-${name}" = lib.mkIf safeRestart safeRestartProgram;

  local.vmHost.nixosShell.instances.${name} = {
    inherit
      buildIntervalSec
      imageServiceBefore
      imageUpdateTimer
      registerImage
      restartVmAfterImageUpdate
      safeRestart
      updateFlakeLocks
      updateImageBeforeStart
      updateOnGuestShutdown
      ;
  };

  environment.systemPackages = [
    updateImageCli
    runVmCli
  ];

  systemd.targets.nixos-shell-images = lib.mkIf registerImage {
    description = "Cache registered nixos-shell VM images";
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.${imageServiceName} = lib.mkIf registerImage {
    description = "VM image manager (nixos-shell) for ${name}";
    wantedBy = [ "nixos-shell-images.target" ];
    after = [ "nix-daemon.service" ] ++ lib.optional updateFlakeLocks "network-online.target";
    wants = lib.optional updateFlakeLocks "network-online.target";
    before = imageServiceBefore;
    restartIfChanged = true;
    restartTriggers = [ self.outPath ];
    path = [
      pkgs.coreutils
      pkgs.systemd
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = !imageUpdateTimer;
      Restart = "no";
      TimeoutStartSec = "2h";
      User = "root";
    };

    script = ''
      set -euo pipefail
      image_root="''${NIXOS_SHELL_IMAGE_ROOT:-${imgBase}}"
      current_link="$image_root/current"
      previous_link="$image_root/restart-previous"
      nix_store_bin="''${NIXOS_SHELL_NIX_STORE_BIN:-${pkgs.nix}/bin/nix-store}"
      previous_image="$(readlink -e "$current_link" 2>/dev/null || true)"
      ${lib.optionalString restartVmAfterImageUpdate ''
        if [ -n "$previous_image" ]; then
          "$nix_store_bin" \
            --add-root "$previous_link" \
            --indirect \
            --realise "$previous_image" >/dev/null
        fi
      ''}
      update_status=0
      ${updateImageProgram}/bin/update-image-${name} ${automaticUpdateMode} || update_status=$?
      ${lib.optionalString restartVmAfterImageUpdate ''
        candidate="$(readlink -e "$current_link" 2>/dev/null || true)"
        system_state="$(systemctl is-system-running 2>/dev/null || true)"

        if [ "$update_status" -ne 0 ] || [ "$candidate" = "$previous_image" ]; then
          rm -f "$previous_link"
        elif [ "$system_state" = stopping ] \
          || ! systemctl is-active --quiet "${vmServiceName}.service"; then
          rm -f "$previous_link"
        elif ! systemctl start --no-block "${rolloutServiceName}.service"; then
          echo "${name}: failed to schedule the built image rollout" >&2
          update_status=1
        fi
      ''}
      ${lib.optionalString autoStart ''
            if ! systemctl is-active --quiet "${vmServiceName}.service"; then
              systemctl start --no-block "${vmServiceName}.service" || true
            fi
          ''}
      exit "$update_status"
    '';
  };

  systemd.services.${rolloutServiceName} = lib.mkIf (registerImage && restartVmAfterImageUpdate) {
    description = "Activate the built nixos-shell VM image for ${name}";
    after = [ "${imageServiceName}.service" ];
    before = imageServiceBefore;
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "5min";
      User = "root";
    };
    script = ''
      exec ${activateImageProgram}/bin/activate-image-${name}
    '';
  };

  systemd.timers.${imageServiceName} = lib.mkIf (registerImage && imageUpdateTimer) {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "${toString buildDelaySec}s";
      OnUnitInactiveSec = "${toString buildIntervalSec}s";
      Persistent = true;
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
      ConditionPathExists = currentLink;
    };

    after = lib.mkForce (lib.optional updateImageBeforeStart "${imageServiceName}.service");
    wants = lib.mkForce (lib.optional updateImageBeforeStart "${imageServiceName}.service");
    requires = lib.mkForce [ ];
    bindsTo = lib.mkForce [ ];
    partOf = lib.mkForce [ ];
    wantedBy = lib.mkForce [ ];

    path = [
      pkgs.socat
      pkgs.coreutils
      pkgs.tmux
      pkgs.bash
      pkgs.qemu
    ];

    serviceConfig =
      {
        Type = "simple";
        Restart = "always";
        RestartSec = restartTime;
        User = "root";
        KillMode =
          if registerImage && updateOnGuestShutdown then
            "control-group"
          else
            "process";
        TimeoutStopSec =
          if registerImage && updateOnGuestShutdown then
            "2h"
          else
            "2min";
        WorkingDirectory = workingDir;
        ExecStart = stableLauncher;

        ExecStop = pkgs.writeShellScript "stop-${vmServiceName}" ''
          set -euo pipefail
          mkdir -p "${tmuxDir}"
          : > "${stopMarker}"
          if [ -S "${qmpSocket}" ]; then
          printf '%s\n' \
          '{"execute":"qmp_capabilities"}' \
          '{"execute":"system_powerdown"}' \
          | ${pkgs.socat}/bin/socat - UNIX-CONNECT:"${qmpSocket}" || true
          fi
          sleep 5
          tmux -S "${tmuxSocket}" kill-session -t "${tmuxSession}" 2>/dev/null || true
        '';
      }
      // lib.optionalAttrs (registerImage && updateOnGuestShutdown) {
        ExecStopPost = updateAfterGuestShutdown;
      };
  };

  systemd.timers.${vmServiceName} = lib.mkIf autoStart {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1";
      Unit = "${vmServiceName}.service";
    };
  };

  systemd.tmpfiles.rules = [
    "L+ ${stableLauncher} - - - - ${innerStart}"
    (lib.optionalString registerImage "L+ ${tmuxDir}/${name}-update-image - - - - ${updateImageProgram}/bin/update-image-${name}")
    "d ${workingDir} 0755 root root -"
    "d ${persistDir} 0755 root root -"
    "d ${perVmPersistDir} 0755 root root -"
    "d ${imgBase} 0755 root root -"
    "d ${runImgBase} 0755 root root -"
    "d ${tmuxDir} 0755 root root -"
    (lib.optionalString pinned "f ${pinLock}  0644 root root - -")
    (lib.optionalString safeRestart "L+ /root/${name}.sh - - - - ${lib.getExe safeRestartProgram}")
  ]
  ++ extraTmpfiles;
}
