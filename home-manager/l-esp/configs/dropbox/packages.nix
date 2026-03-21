{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  unstablePkgs = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfree = true;
  };
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
      After = [ "network-online.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
    Service = {
      ExecStart = "${pkgs.maestral-gui}/bin/maestral_qt";
      Restart = "on-failure";
    };
  };
}
