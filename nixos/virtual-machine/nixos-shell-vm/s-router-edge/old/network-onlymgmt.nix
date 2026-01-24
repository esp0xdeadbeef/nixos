{
  config,
  pkgs,
  lib,
  ...
}:
{

  environment.systemPackages = with pkgs; [
    # coreutils
    # python3
    # coreutils
    dnsutils # dig
    wireguard-tools
    tcpdump
    traceroute
    nftables
    dhcpcd
    tmux
  ];

  networking.networkmanager.enable = false;

  systemd.network.networks."10-mgmt" = {
    matchConfig.Name = "eth0";
    networkConfig.DHCP = "yes";
    routingPolicyRules = [
      {
        Priority = 100;
        From = "192.168.1.0/24";
        Table = "main";
      }
    ];
  };


  networking.useNetworkd = true;

  # Disable networkd-wait-online
  systemd.services.systemd-networkd-wait-online.enable = pkgs.lib.mkForce false;
}
