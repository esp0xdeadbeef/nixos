{ ... }:
{
  programs.thunderbird.enable = true;

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "message/rfc822" = [ "thunderbird.desktop" ];
      "x-scheme-handler/mailto" = [ "thunderbird.desktop" ];
    };
  };
}
