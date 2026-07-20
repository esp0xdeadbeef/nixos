{ inputs
, lib
, pkgs
, self
, ...
}:
let
  qgaHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";
  qgaSocket = "/run/nixos-shell-vm-manager/s-test-l-esp/qga.sock";
in
{
  services.nixosShellVmManager = {
    enable = true;
    maxConcurrentBuilds = 1;
    persistentDirectory = "/persist/vm-persists";

    instances.s-test-l-esp = {
      description = "l-esp test VM (nixos-shell)";
      image = self.nixosConfigurations.s-test-l-esp.config.system.build.nixos-shell;
      activation.startOnBoot = false;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe qgaHealth)
          qgaSocket
        ];
        timeoutSeconds = 10;
        retries = 60;
        intervalSeconds = 2;
      };
      runner.qemuArguments = [
        "-chardev"
        "socket,id=qga0,path=${qgaSocket},server=on,wait=off"
        "-device"
        "virtserialport,chardev=qga0,name=org.qemu.guest_agent.0"
      ];
      storage.persistentDisk = {
        enable = true;
        fileName = "state.qcow2";
        size = "20G";
      };
      runner.stopGraceSeconds = 60;
    };
  };
}
