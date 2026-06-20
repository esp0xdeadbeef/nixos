{ profiles, ... }:
{
  imports = [
    profiles.nixos.base.default
    profiles.nixos.desktop.common
    profiles.nixos.network.workstation
    profiles.nixos.packages.workstation
    profiles.nixos.virtualization.host
  ];
}
