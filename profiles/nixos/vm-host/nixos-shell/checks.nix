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
      rolloutServiceName = "${name}-rollout";
      vmService = config.systemd.services.${vmServiceName} or { };
      imageService = config.systemd.services.${imageServiceName} or { };
      rolloutService = config.systemd.services.${rolloutServiceName} or { };
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
        assertion = !instance.restartVmAfterImageUpdate || instance.registerImage;
        message = "${name}: restartVmAfterImageUpdate requires registerImage";
      }
      {
        assertion = !(instance.updateImageBeforeStart && instance.restartVmAfterImageUpdate);
        message = "${name}: VM startup and post-build rollout modes are mutually exclusive";
      }
      {
        assertion = !instance.restartVmAfterImageUpdate || !instance.updateOnGuestShutdown;
        message = "${name}: automatic rollout must not trigger a second guest-shutdown image build";
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
          !instance.restartVmAfterImageUpdate
          || (
            !builtins.elem "${imageServiceName}.service" (vmService.after or [ ])
            && !builtins.elem "${imageServiceName}.service" (vmService.wants or [ ])
            && builtins.hasAttr rolloutServiceName config.systemd.services
            && builtins.elem "${imageServiceName}.service" (rolloutService.after or [ ])
            && lib.hasInfix
              "systemctl start --no-block \"${rolloutServiceName}.service\""
              (imageService.script or "")
          );
        message = "${name}: post-build rollout must never block VM startup";
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
          !instance.restartVmAfterImageUpdate
          || builtins.all
            (unit: builtins.elem unit (rolloutService.before or [ ]))
            instance.imageServiceBefore;
        message = "${name}: production rollout must finish before dependent image services";
      }
      {
        assertion =
          !instance.updateFlakeLocks
          || !instance.registerImage
          || lib.hasInfix "update-image-${name} --force" (imageService.script or "");
        message = "${name}: flake-lock updates must force a fresh input resolution";
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
      && instance.updateFlakeLocks
      && instance.updateOnGuestShutdown)
    instanceNames;

  safeRestartNames = builtins.filter
    (name:
      instances.${name}.safeRestart
      && instances.${name}.restartVmAfterImageUpdate)
    instanceNames;

  rolloutTestNames = builtins.filter
    (name: instances.${name}.restartVmAfterImageUpdate)
    instanceNames;

  shutdownTestName =
    if shutdownTestNames == [ ] then null else builtins.head shutdownTestNames;
  safeRestartName =
    if safeRestartNames == [ ] then null else builtins.head safeRestartNames;
  rolloutTestName =
    if rolloutTestNames == [ ] then null else builtins.head rolloutTestNames;

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
          ${config.system.build."activateVmImage-${safeRestartName}"}/bin/activate-image-${safeRestartName} \
          ${safeRestartName}
      ''}

      ${lib.optionalString (rolloutTestName != null) ''
        ${pkgs.bash}/bin/bash tests/test-image-rollout.sh \
          ${config.system.build."activateVmImage-${rolloutTestName}"}/bin/activate-image-${rolloutTestName} \
          ${rolloutTestName}

        ${pkgs.bash}/bin/bash tests/test-image-rollout-flow.sh \
          ${pkgs.writeShellScript "${rolloutTestName}-image-service-test" config.systemd.services."${rolloutTestName}-image".script} \
          ${config.system.build."activateVmImage-${rolloutTestName}"}/bin/activate-image-${rolloutTestName} \
          ${rolloutTestName}
      ''}

      touch "$out"
    '';

  hasLifecycleTests =
    shutdownTestName != null || safeRestartName != null || rolloutTestName != null;
in
{
  assertions = lib.concatMap assertionsFor instanceNames;

  system.build.nixosShellVmLifecycleCheck =
    lib.mkIf hasLifecycleTests lifecycleCheck;
  system.extraDependencies =
    lib.optional hasLifecycleTests lifecycleCheck;
}
