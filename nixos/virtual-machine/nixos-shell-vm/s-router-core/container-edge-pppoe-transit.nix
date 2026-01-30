{
  config,
  pkgs,
  lib,
  ...
}:

let
  lanIf = "eth0"; # full LAN trunk
  wanIf = "eth1"; # full WAN trunk
in
{
  ## Secrets
  sops.secrets.pppoe-username = { };
  sops.secrets.pppoe-password = { };

  ## Host network backend (host only keeps management)
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;

  ##########################################################################
  # NO VLANs, NO bridges, NO netdevs, NO networks for eth0/eth1
  # They are passed RAW into the container.
  ##########################################################################

  ## Container = real router
  containers.pppoe-wan-to-downstream = {
    autoStart = false;
    privateNetwork = true;

    # Pass raw trunks
    #extraVeths = {
    #  lan.hostInterface = lanIf;  # full LAN trunk
    #  wan.hostInterface = wanIf;  # full WAN trunk
    #};
    extraVeths = {
      lan.hostBridge = "br-lan-trunk";
      wan.hostBridge = "br-wan-trunk";
    };

    allowedDevices = [
      {
        node = "/dev/ppp";
        modifier = "rw";
      }
    ];

    bindMounts = {
      "/dev/ppp" = {
        hostPath = "/dev/ppp";
        isReadOnly = false;
      };

      "/run/secrets/pppoe-username" = {
        hostPath = config.sops.secrets.pppoe-username.path;
        isReadOnly = true;
      };

      "/run/secrets/pppoe-password" = {
        hostPath = config.sops.secrets.pppoe-password.path;
        isReadOnly = true;
      };
    };

    additionalCapabilities = [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
    ];

    # Container does ALL routing now
    config = ./container;
  };
}
