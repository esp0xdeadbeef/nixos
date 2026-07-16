{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.local.vmHost.nixosShell;
  instances = cfg.instances;
  instanceNames = builtins.attrNames instances;

  assertionsFor =
    name:
    let
      instance = instances.${name};
      vmServiceName = "${name}-vm";
      imageServiceName = "${name}-image";
      vmService = config.systemd.services.${vmServiceName} or { };
      imageService = config.systemd.services.${imageServiceName} or { };
      imageTimer = config.systemd.timers.${imageServiceName} or { };
      stopPost = vmService.serviceConfig.ExecStopPost or null;
    in
    [
      {
        assertion = !instance.updateImageBeforeStart || instance.registerImage;
        message = "${name}: updateImageBeforeStart requires registerImage";
      }
      {
        assertion = !instance.imageUpdateTimer || instance.registerImage;
        message = "${name}: imageUpdateTimer requires registerImage";
      }
      {
        assertion = !instance.safeRestart || instance.registerImage;
        message = "${name}: safeRestart requires registerImage";
      }
      {
        assertion =
          !instance.updateImageBeforeStart
          || (
            builtins.elem "${imageServiceName}.service" (vmService.after or [ ])
            && builtins.elem "${imageServiceName}.service" (vmService.wants or [ ])
          );
        message = "${name}: the image service must run before the VM service";
      }
      {
        assertion =
          !instance.imageUpdateTimer
          || (
            builtins.hasAttr imageServiceName config.systemd.timers
            && (imageTimer.timerConfig.OnUnitInactiveSec or null)
            == "${toString instance.buildIntervalSec}s"
            && (imageService.serviceConfig.RemainAfterExit or true) == false
          );
        message = "${name}: image refresh timer must run after the previous update completed";
      }
      {
        assertion =
          !instance.registerImage
          || builtins.all
            (unit:
              builtins.elem unit (imageService.before or [ ])
              && builtins.hasAttr (lib.removeSuffix ".service" unit) config.systemd.services)
            instance.imageServiceBefore;
        message = "${name}: imageServiceBefore references a missing or unordered image service";
      }
      {
        assertion =
          !instance.rebuildFromLatestLocks
          || !instance.registerImage
          || lib.hasInfix "update-image-${name} --force" (imageService.script or "");
        message = "${name}: latest-lock image updates must force a refreshed flake resolution";
      }
      {
        assertion =
          if instance.registerImage && instance.updateOnGuestShutdown then
            stopPost != null
            && (vmService.serviceConfig.KillMode or null) == "control-group"
            && (vmService.serviceConfig.TimeoutStopSec or null) == "2h"
          else
            stopPost == null;
        message = "${name}: guest-shutdown image update lifecycle is inconsistent";
      }
    ];

  shutdownTestNames = builtins.filter
    (name:
      let
        instance = instances.${name};
      in
      instance.registerImage
      && instance.rebuildFromLatestLocks
      && instance.updateOnGuestShutdown)
    instanceNames;

  safeRestartNames = builtins.filter
    (name: instances.${name}.safeRestart)
    instanceNames;

  shutdownTestName =
    if shutdownTestNames == [ ] then null else builtins.head shutdownTestNames;
  safeRestartName =
    if safeRestartNames == [ ] then null else builtins.head safeRestartNames;

  lifecycleCheck = pkgs.runCommand "nixos-shell-vm-lifecycle-check"
    {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.util-linux
      ];
    }
    ''
      cp -R ${./tests} tests
      chmod -R u+w tests
      patchShebangs tests

      ${lib.optionalString (shutdownTestName != null) ''
        ${pkgs.bash}/bin/bash tests/test-image-updater.sh \
          ${config.system.build."vmImageUpdater-${shutdownTestName}"}/bin/update-image-${shutdownTestName} \
          ${shutdownTestName} \
          ${config.systemd.services."${shutdownTestName}-vm".serviceConfig.ExecStopPost}
      ''}

      ${lib.optionalString (safeRestartName != null) ''
        ${pkgs.bash}/bin/bash tests/test-safe-restart.sh \
          ${config.system.build."safeRestart-${safeRestartName}"}/bin/restart-${safeRestartName} \
          ${safeRestartName}
      ''}

      touch "$out"
    '';

  hasLifecycleTests = shutdownTestName != null || safeRestartName != null;
in
{
  assertions = lib.concatMap assertionsFor instanceNames;

  system.build.nixosShellVmLifecycleCheck =
    lib.mkIf hasLifecycleTests lifecycleCheck;
  system.extraDependencies =
    lib.optional hasLifecycleTests lifecycleCheck;
}
