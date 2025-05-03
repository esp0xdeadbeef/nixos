{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    dropbox
    libappindicator-gtk3
    # sni-qt
  ];

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
