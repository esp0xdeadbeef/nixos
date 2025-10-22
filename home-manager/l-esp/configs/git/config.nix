{
  config,
  lib,
  pkgs,
  sopsSecrets,
  ...
}:
{
  programs.git.settings.user = {
    email = "esp0xdeadbeef@gmail.com";
    name = "esp0xdeadbeef";

  };
  programs.git = {
    enable = true;
    #   userName = "esp0xdeadbeef";
    #   userEmail = "esp0xdeadbeef@gmail.com";
  };
}
