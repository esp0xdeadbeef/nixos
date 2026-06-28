{ outPath, pkgs, profiles, ... }:
{
  imports = [
    profiles.nixos.base.common
    profiles.nixos.editors.neovim
    "${outPath}/library/01-general/packages/window-managers/X-org/packages.nix"
    "${outPath}/library/01-general/packages/window-managers/X-org/i3-wm/packages.nix"
  ];

  programs.nano.enable = false;

  environment.systemPackages = with pkgs; [
    binutils
    btop
    sshpass
    tmuxp
    vim
  ];
}
