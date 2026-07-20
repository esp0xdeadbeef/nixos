{ startOnBootInstances ? [ "s-test" ] }:
{ config
, inputs
, lib
, pkgs
, self
, ...
}:
let
  guestAgentHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";

  qgaSocketFor = vmName: "/run/nixos-shell-vm-manager/${vmName}/qga.sock";

  qgaHealthCommandFor =
    vmName:
    lib.escapeShellArgs [
      (lib.getExe guestAgentHealth)
      (qgaSocketFor vmName)
    ];

  qgaArgumentsFor = vmName: [
    "-chardev"
    "socket,id=qga0,path=${qgaSocketFor vmName},server=on,wait=off"
    "-device"
    "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
  ];

  routerCriticalUnits = [
    "systemd-networkd.service"
    "container@access-vlan2.service"
    "container@access-vlan3.service"
    "container@access-vlan7.service"
    "container@core.service"
    "container@downstream-selector.service"
    "container@policy.service"
    "container@upstream-selector.service"
  ];

  routerUnitHealthCommand = ''
    status=0
    for unit in "$@"; do
      if state=$(/run/current-system/sw/bin/systemctl is-active "$unit" 2>&1); then
        :
      else
        status=1
      fi
      printf '%s=%s\n' "$unit" "$state"
    done
    exit "$status"
  '';

  vms = [
    {
      name = "s-infra";
      description = "Infra VM (nixos-shell)";
    }
    {
      name = "s-nebula";
      description = "Nebula VM (nixos-shell)";
    }
    {
      name = "s-agents";
      description = "Agent workbench VM (nixos-shell)";
    }
    {
      name = "s-router-legacy-edge";
      description = "s-router-legacy-edge VM (nixos-shell)";
    }
    {
      name = "s-router-legacy-core";
      description = "s-router-core VM (nixos-shell)";
    }
    {
      name = "s-router-clab";
      description = "s-router-clab VM (nixos-shell)";
      activation.refreshPins = true;
    }
    {
      name = "s-router-nixos";
      description = "s-router-nixos VM (nixos-shell)";
      activation.refreshPins = true;
    }
    {
      name = "s-router-prod";
      description = "Production router canary VM (nixos-shell)";
      activation.rolloutCandidateOnGuestShutdown = false;
      healthCheck = {
        command = lib.escapeShellArgs (
          [
            (lib.getExe guestAgentHealth)
            (qgaSocketFor "s-router-prod")
            "/run/current-system/sw/bin/bash"
            "-c"
            routerUnitHealthCommand
            "qga-systemd-health"
          ]
          ++ routerCriticalUnits
        );
        timeoutSeconds = 120;
        retries = 60;
        intervalSeconds = 3;
      };
    }
    {
      name = "s-router-legacy-prod";
      description = "Legacy production router fallback VM (nixos-shell)";
      runnerRelativePath = "bin/run-s-router-prod-vm";
    }
    {
      name = "s-router-test-clients";
      description = "s-router-test-clients VM (nixos-shell)";
      activation.refreshPins = true;
    }
    {
      name = "s-router-vpn-egress";
      description = "VPN-egress VM (nixos-shell)";
    }
    {
      name = "s-gameserver";
      description = "Gameserver VM (nixos-shell)";
    }
    {
      name = "s-test";
      description = "s-test (nixos-shell)";
    }
  ];

  vmNames = map (vm: vm.name) vms;
  unknownStartOnBootInstances = lib.subtractLists vmNames startOnBootInstances;

  mkInstance = vm: {
    inherit (vm) name;
    value = {
      inherit (vm) description;
      image = self.nixosConfigurations.${vm.name}.config.system.build.nixos-shell;
      activation = {
        startOnBoot = builtins.elem vm.name startOnBootInstances;
      }
      // (vm.activation or { });
      healthCheck = vm.healthCheck or {
        command = qgaHealthCommandFor vm.name;
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      storage.persistentDisk = {
        enable = true;
        fileName = "state.qcow2";
        size = "100G";
      };
      runner = {
        stopGraceSeconds = 60;
        qemuArguments = qgaArgumentsFor vm.name ++ (vm.qemuArguments or [ ]);
      }
      // lib.optionalAttrs (vm ? runnerRelativePath)
        {
          relativePath = vm.runnerRelativePath;
        };
    }
    // lib.optionalAttrs (vm.activation.refreshPins or false) {
      pinRefresh = {
        flake = self.outPath;
        flakeAttribute = "nixosConfigurations.${vm.name}.config.system.build.nixos-shell";
      };
    };
  };
in
{
  assertions = [
    {
      assertion = unknownStartOnBootInstances == [ ];
      message = "Unknown nixos-shell start-on-boot instances: ${lib.concatStringsSep ", " unknownStartOnBootInstances}";
    }
  ];

  services.nixosShellVmManager = {
    enable = true;
    maxConcurrentBuilds = 1;
    persistentDirectory = "/persist/vm-persists";
    instances = lib.listToAttrs (map mkInstance vms);
  };

  system.build.vmImages = lib.mapAttrs (_: instance: instance.image) (
    lib.filterAttrs (_: instance: instance.enable) config.services.nixosShellVmManager.instances
  );
}
