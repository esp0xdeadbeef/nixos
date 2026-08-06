{ relativeRepo
, profiles
, ...
}:
{
  imports = [
    profiles.nixos.laptop.autorandr-default
    profiles.nixos.laptop.dock
    profiles.nixos.laptop.monitor-layouts
    profiles.nixos.laptop.power
    profiles.nixos.laptop.xlayoutdisplay-hotplug
    (relativeRepo.module "library/01-general/packages/password-managers/1password.nix")
  ];

  local.shell.zshPrompt = {
    enable = true;
  };
}
