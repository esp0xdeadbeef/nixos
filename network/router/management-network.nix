{ config, pkgs, ... }:

{
  # networking = {
  #   interfaces = {
  #     enp0s18.useDHCP = true;
  #     enp0s19.useDHCP = false;

  #     vlan004.useDHCP = true;
  #     vlan005.useDHCP = true;

  #     # Uncomment this to use static instead of DHCP
  #     # vlan004.ipv4.addresses = [{
  #     #   address = "10.1.1.2";
  #     #   prefixLength = 24;
  #     # }];
  #     # vlan005.ipv4.addresses = [{
  #     #   address = "10.10.10.3";
  #     #   prefixLength = 24;
  #     # }];
  #   };

  #   vlans = {
  #     vlan004 = {
  #       id = 4;
  #       interface = "ens19";
  #     };
  #     vlan005 = {
  #       id = 5;
  #       interface = "ens19";
  #     };
  #   };
  # };
  networking = {
    useNetworkd = false;
    useDHCP = false; # off by defalut, enable per-interface
    # zfs needs hostId, so we derive it from hostname
    hostId = lib.mkDefault (
      builtins.substring 0 8 (builtins.hashString "md5" config.networking.hostName)
    );
    firewall.enable = false; # let's not complicate things while debugging
    bridges = {
      "lan" = {
        interfaces = [ "enp0s19" ]; # sits on top of eth0
      };
    };

    vlans = {
      vlan2 = {
        id = 2;
        interface = "lan";
      };
      vlan398 = {
        id = 398;
        interface = "lan";
      };
    };

    interfaces = {
      enp0s18.useDHCP = true; # Management network
      # eth0.useDHCP = false; # Interface is bridged
      br0.useDHCP = false; # Bridge gets IP via DHCP
      vlan2.useDHCP = true; # VLAN 50 gets IP via DHCP
      vlan398 = {
        ipv4.addresses = [
          {
            address = "10.99.99.30";
            prefixLength = 24;
          }
        ];
      };
    };
  };

}
