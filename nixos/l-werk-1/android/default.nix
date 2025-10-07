{ config, pkgs, ... }:

{
  # Packages required for Waydroid and the Cage compositor
  environment.systemPackages = with pkgs; [
    waydroid
    cage
    lxc
    dbus
  ];

  # Ensure the Waydroid container service is enabled at boot
  systemd.services.waydroid-container = {
    description = "Waydroid Android container";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.waydroid}/bin/waydroid container start";
      ExecStop = "${pkgs.waydroid}/bin/waydroid container stop";
      Restart = "on-failure";
    };
  };

  # User service for launching Android UI inside Cage
  systemd.user.services."waydroid-cage" = {
    description = "Launch Waydroid Android UI in Cage";
    after = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.cage}/bin/cage ${pkgs.waydroid}/bin/waydroid show-full-ui";
      Restart = "on-failure";
    };
  };
}