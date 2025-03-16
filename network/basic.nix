{ config, pkgs, ... }: {  
  #############################
  # Networking and Localization
  #############################
  networking.hostName = "l-werk";
  hardware.bluetooth.enable = true;
  programs.nm-applet.enable = true;
  services.blueman.enable = true;
  networking.networkmanager.enable = true;
  time.timeZone = "Europe/Amsterdam";


  #############################
  # Firewall rules
  # TIP:
  # Use:
  # nixos-firewall-tool reset # to close all ports.
  # Use:
  # nixos-firewall-tool open tcp 8888 # to open a specific port :)
  #############################
  # required for lxc network, no clue how this works:
  networking.nat = {
    enable = true;
    internalInterfaces = ["lxcbr-+" "lxcbr-+"];
    #externalInterfaces = ["wlp0s20f3" "enp0s13f0u4u2"];
    #externalInterface = "ens3";
    # Lazy IPv6 connectivity for the container
    enableIPv6 = true;
  };


  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 
      #80 
      #443 
    ];
    allowedTCPPortRanges = [
	#{ from = 0; to = 65535; }
    ];
    allowedUDPPortRanges = [
      #{ from = 0; to = 65535; }
      #{ from = 8000; to = 8010; }
    ];
    # Allow traffic on LXC bridge
    trustedInterfaces = [ "lxcbr0" ];

  };
}
