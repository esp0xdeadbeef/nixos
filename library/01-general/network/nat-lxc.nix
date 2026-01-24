{ config, pkgs, ... }: {  
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
}