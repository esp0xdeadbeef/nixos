{
  config,
  pkgs,
  lib,
  ...
}:

let
  gsettingsDataDirs = map (pkg: lib.removeSuffix "/glib-2.0/schemas" (pkgs.glib.getSchemaPath pkg)) [
    pkgs.gsettings-desktop-schemas
    pkgs.gtk3
    pkgs.maestral-gui
  ];

  maestralXdgDataDirs = lib.concatStringsSep ":" (
    gsettingsDataDirs
    ++ [
      "${pkgs.maestral-gui}/share"
      "${config.home.profileDirectory}/share"
      "/run/current-system/sw/share"
    ]
  );
in
{
  home.packages = with pkgs; [
    maestral-gui
  ];

  home.file."Dropbox".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Documents/Dropbox_maestral";

  systemd.user.services.maestral = {
    Unit = {
      Description = "Maestral Dropbox Client";
      After = [
        "graphical-session.target"
        "network-online.target"
      ];
      PartOf = [ "graphical-session.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.maestral-gui}/bin/maestral_qt";
      Environment = [
        "XDG_DATA_DIRS=${maestralXdgDataDirs}"
      ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
