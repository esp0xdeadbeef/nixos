{ lib, relativeRepo, ... }:
{
  imports = [
    ./base.nix
    (relativeRepo.module "profiles/home-manager/desktop/pentest-windows.nix")
    (relativeRepo.module "home-manager/01-general/darkmode/config.nix")
    (relativeRepo.module "home-manager/01-general/editors/vscode.nix")
    (relativeRepo.module "home-manager/01-general/pdf-reader/packages.nix")
    (relativeRepo.module "home-manager/01-general/virt-manager-config/default.nix")
    (relativeRepo.module "profiles/home-manager/nix/github-access-token.nix")
  ];

  local.i3.spotify.enable = lib.mkDefault true;
}
