{
  config,
  pkgs,
  hostname,
  ...
}:
{
  #############################
  # Networking and Localization
  #############################
  networking.hostName = hostname;
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Amsterdam";

}
