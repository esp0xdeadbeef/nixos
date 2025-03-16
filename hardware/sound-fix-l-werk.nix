{ config, pkgs, ... }:

{
  # Ensure the environment has the necessary package
  environment.systemPackages = with pkgs; [
    alsa-utils
  ];

  # Define a systemd service to run alsactl init on every reboot
  systemd.services.alsaInit = {
    wantedBy = [ "multi-user.target" ];
    after = [ "sound.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.alsa-utils}/bin/alsactl init";
    };
  };
}

