{ relativeRepo, ... }:
{
  imports = [
    (relativeRepo.module "profiles/home-manager/desktop/window-manager.nix")
    (relativeRepo.module "profiles/home-manager/desktop/pentest-windows.nix")
    (relativeRepo.module "home-manager/01-general/darkmode/config.nix")
    (relativeRepo.module "home-manager/01-general/editors/vscode.nix")
    (relativeRepo.module "home-manager/01-general/pdf-reader/packages.nix")
    (relativeRepo.module "home-manager/01-general/virt-manager-config/default.nix")
    (relativeRepo.module "profiles/home-manager/nix/github-access-token.nix")
    (relativeRepo.module "home-manager/03-window-manager-sway/wayland/sway/configs.nix")
    (relativeRepo.module "home-manager/02-window-manager-i3/i3status-rust/packages.nix")
  ];
}
