{ config, pkgs, hostname, ... }: {  
  #############################
  # Networking and Localization
  #############################
  #networking.hostName = "l-werk";
  networking.hostName = hostname;
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Amsterdam";


  # new rule to allow wireguard through:
  networking.firewall.checkReversePath = false;


}
