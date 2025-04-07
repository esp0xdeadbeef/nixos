{
  config,
  pkgs,
  ...
}:
{
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Amsterdam";
}
