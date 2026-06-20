{ profiles, ... }:
{
  imports = [
    profiles.nixos.laptop.dock
    profiles.nixos.laptop.power
  ];
}
