{ pkgs
, profiles
, self
, ...
}:
{
  imports = [
    profiles.nixos.vm-host.nixos-shell-v2
  ];

  services.nixosShellVmManager = {
    enable = true;
    maxConcurrentBuilds = 1;
    persistentDirectory = "/persist/vm-persists";

    instances.s-test-l-esp = {
      description = "l-esp test VM (nixos-shell)";
      image = self.nixosConfigurations.s-test-l-esp.config.system.build.nixos-shell;
      activation.startOnBoot = false;
      healthCheck.command =
        "${pkgs.openssh}/bin/ssh-keyscan -T 2 -p 2222 127.0.0.1 >/dev/null";
      storage.persistentDisk = {
        enable = true;
        fileName = "state.qcow2";
        size = "20G";
      };
      runner.stopGraceSeconds = 60;
    };
  };
}
