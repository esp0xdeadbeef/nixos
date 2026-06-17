{ profiles, ... }:
{
  imports = [
    profiles.nixos.base
    profiles.nixos.desktop.common
    profiles.nixos.packages.workstation
    profiles.nixos.virtualization.host
  ];
}
