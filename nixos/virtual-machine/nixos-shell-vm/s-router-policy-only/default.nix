# ./default.nix
# FILE: s-router-policy-only/default.nix
{ outPath, lib, config, ... }:

{
  imports = [
    # Host-side router base (provides vm + networkd baseline)
    #"${outPath}/library/10-vms/nixos-shell-vm/host-config-router"
    ./host-config
    # Local overrides / wiring
    ./mount-utils.nix
    ./container-settings.nix
    ./nftables.nix
    ./debugging-packages.nix
  ];

  networking.hostName = "s-router-policy-only";

  networking.useNetworkd = true;
  systemd.network.enable = true;
  networking.useDHCP = false;

  system.stateVersion = "25.11";
}

