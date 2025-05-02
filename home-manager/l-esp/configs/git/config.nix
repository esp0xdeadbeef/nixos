{
  config,
  lib,
  pkgs,
  sopsSecrets,
  ...
}:
{
  programs.git = {
  enable    = true;
  userName  = "esp0xdeadbeef";
  userEmail = "esp0xdeadbeef@gmail.com";
};
}