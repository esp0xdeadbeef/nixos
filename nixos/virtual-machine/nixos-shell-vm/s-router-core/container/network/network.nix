# ./container/network/network.nix
{ ... }:
{
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  systemd.network.enable = true;
}
