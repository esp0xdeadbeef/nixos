{
  config,
  lib,
  pkgs,
  sopsSecrets,
  ...
}:

{
  home.file."/.config/flameshot/flameshot.ini" = {
    text = ''
      [General]
      ; check https://github.com/flameshot-org/flameshot/blob/master/flameshot.example.ini
      ; Image Save Path
      savePath=${config.home.homeDirectory}/Pictures
    '';
  };
}
