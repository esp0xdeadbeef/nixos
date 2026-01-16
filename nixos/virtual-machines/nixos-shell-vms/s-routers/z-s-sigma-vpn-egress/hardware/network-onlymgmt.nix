{
  config,
  pkgs,
  lib,
  ...
}:

let
  management_interface = "eth0";
in
{

  environment.systemPackages = with pkgs; [
    # coreutils
    # python3
    # coreutils
    dnsutils # dig
    openvpn
    wireguard-tools
    tcpdump
    traceroute
    nftables
    dhcpcd
    tmux
  ];

  networking.networkmanager.enable = false;

  #networking = {
  #  interfaces.ens18 = {
  #    ipv4.addresses = [
  #      {
  #        address = "192.168.1.3";
  #        prefixLength = 24;
  #      }
  #    ];
  #  };
  #  defaultGateway = {
  #    address = "192.168.1.1";
  #    interface = "ens18";
  #  };
  #};
  #networking.interfaces.ens18.useDHCP = true;
networking = {
  useNetworkd = true;
  interfaces."${management_interface}".useDHCP = true;
};

  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
