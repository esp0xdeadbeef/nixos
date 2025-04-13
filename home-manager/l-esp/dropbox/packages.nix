{ config, pkgs, ... }:
{
  home.packages = with pkgs; [
    dropbox
  ];

  systemd.user.services.dropbox = {
    # description = "Dropbox service";
    # wantedBy = [ "default.target" ];
    # # after = "network-online.target";

    # serviceConfig = {
    #   ExecStart = "${pkgs.dropbox}/bin/dropbox";
    #   After = "network-online.target";  # ✅ this is correct

    #   Restart = "on-failure";
    # };
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
