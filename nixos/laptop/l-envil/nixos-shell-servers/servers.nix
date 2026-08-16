{ inputs
, lib
, pkgs
, self
, ...
}:
let
  guestAgentHealth =
    inputs.nixos-shell-vm-manager.packages.${pkgs.stdenv.hostPlatform.system}."qga-systemd-health";
  qgaSocket = "/run/nixos-shell-vm-manager/s-router-cobalt/qga.sock";
in
{
  services.nixosShellVmManager = {
    enable = true;
    maxConcurrentBuilds = 1;
    persistentDirectory = "/persist/vm-persists";

    instances.s-router-cobalt = {
      description = "cobalt site router (nixos-shell)";
      image = self.nixosConfigurations.s-router-cobalt.config.system.build.nixos-shell;
      activation.startOnBoot = true;
      healthCheck = {
        command = lib.escapeShellArgs [
          (lib.getExe guestAgentHealth)
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
        "-usb"
        "-device"
        "usb-host,vendorid=0x148f,productid=0x3070"
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
