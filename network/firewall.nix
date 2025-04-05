
{ config, pkgs, ... }: {  

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