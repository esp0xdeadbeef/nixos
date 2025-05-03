{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    dropbox
    libappindicator-gtk3
    # sni-qt
  ];
  home.file."Dropbox".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/Documents/Dropbox";
  systemd.user.services.dropbox = {
    Unit = {
      Description = "Dropbox service";
      After = [ "network-online.target" ];
    };
    Install = {
      WantedBy = [ "default.target" ];
    };

    Service = {
      ExecStart = "${pkgs.dropbox}/bin/dropbox";
      Restart = "on-failure";
    };
  };

}
