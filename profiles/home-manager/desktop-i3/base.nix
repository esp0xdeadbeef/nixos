{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "home-manager/02-window-manager-i3/i3/packages.nix")
    (relativeRepo.module "home-manager/02-window-manager-i3/i3status-rust/packages.nix")
  ];
}
