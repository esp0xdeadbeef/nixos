{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv) system;
    config.allowUnfree = true;
  };
in
{
  # Install Maestral with GUI and tray support
  home.packages = with pkgs; [
    maestral-gui
  ];

  # Symlink Dropbox-like folder (Maestral uses ~/Maestral by default but this overrides)
  home.file."Dropbox".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Documents/Dropbox_maestral";

  # Optional: autostart Maestral as a user service
  systemd.user.services.maestral = {
    Unit = {
      Description = "Maestral Dropbox Client";
      After = [ "network-online.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      ExecStart = "${pkgs.maestral-gui}/bin/maestral_qt ";
      Restart = "on-failure";
    };
  };
}
