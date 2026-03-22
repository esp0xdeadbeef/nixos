{
  outPath,
  lib,
  config,
  ...
}:

let
  inventory = import ../inventory.nix { inherit lib outPath; };

  rendered = import ../lib/renderer/render-host-network.nix {
    inherit lib inventory;
    hostName = config.networking.hostName;
  };
in
{
  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  systemd.network.netdevs = rendered.netdevs;
  systemd.network.networks = rendered.networks;
}
