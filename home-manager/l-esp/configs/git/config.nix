{
  config,
  lib,
  pkgs,
  sopsSecrets,
  ...
}:
{
  programs.git = {
    enable = true;
    signing.format = null;
    settings.user = {
      email = "esp0xdeadbeef@gmail.com";
      name = "esp0xdeadbeef";

    };
  };
}
